import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  PredictionResult
//  Data class untuk membawa hasil prediksi keluar dari PredictionService.
// ─────────────────────────────────────────────────────────────────────────────
class PredictionResult {
  /// Label huruf yang sudah stabil (A-Z), atau string kosong '' jika:
  ///   - confidence < threshold
  ///   - debounce belum terpenuhi (huruf belum muncul 5x berturut-turut)
  ///   - model belum siap
  final String label;

  /// Probabilitas softmax dari prediksi terbaik (0.0 – 1.0).
  final double confidence;

  /// Semua skor softmax per label. Berguna untuk debug / visualisasi.
  final Map<String, double> allScores;

  /// Status teks yang cocok untuk ditampilkan langsung di UI.
  ///   - "Mendeteksi..."  → model aktif tapi confidence rendah
  ///   - "Memuat Model..."→ model belum selesai di-load
  ///   - huruf (mis "A") → prediksi stabil
  final String displayStatus;

  const PredictionResult({
    required this.label,
    required this.confidence,
    required this.allScores,
    required this.displayStatus,
  });

  static const PredictionResult empty = PredictionResult(
    label: '',
    confidence: 0.0,
    allScores: {},
    displayStatus: 'Mendeteksi...',
  );

  static const PredictionResult loading = PredictionResult(
    label: '',
    confidence: 0.0,
    allScores: {},
    displayStatus: 'Memuat Model...',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  PredictionService
//
//  Satu-satunya class yang perlu kamu panggil dari luar.
//  Tanggung jawab:
//    1. Load TFLite model + scaler JSON
//    2. Menyimpan state kalibrasi (currentMin / currentMax)
//    3. Normalisasi input (MinMax Scaler)
//    4. Inference ke TFLite + confidence threshold
//    5. Debounce / stability control
//
//  ┌─── Cara integrasi ke Stream Bluetooth ───────────────────────────────┐
//  │                                                                       │
//  │  // Di TranslationProvider atau BLEProvider:                          │
//  │  final _service = PredictionService();                                │
//  │  await _service.init();                                               │
//  │                                                                       │
//  │  bleService.dataStream.listen((List<double> features33) {             │
//  │    // ⚠️  features33 = data SETELAH timestamp distrip di BLEService   │
//  │    final result = _service.predict(features33);                       │
//  │    if (result.label.isNotEmpty) {                                     │
//  │      // Huruf sudah stabil — tampilkan ke UI / TTS                    │
//  │      setState(() => currentLetter = result.label);                    │
//  │    }                                                                  │
//  │    // Selalu bisa pakai result.displayStatus untuk status real-time   │
//  │  });                                                                  │
//  │                                                                       │
//  └───────────────────────────────────────────────────────────────────────┘
// ─────────────────────────────────────────────────────────────────────────────
class PredictionService {
  // ───── Konstanta ────────────────────────────────────────────────────────────

  /// Jumlah fitur input model (Quaternion + sudut PIP/DIP/IP).
  static const int kFeatureCount = 33;

  /// Threshold probabilitas minimum agar prediksi dianggap valid.
  /// Di bawah ini → kembalikan status "Mendeteksi..."
  static const double kConfidenceThreshold = 0.65;

  /// Jumlah frame berturut-turut dengan huruf SAMA agar output dianggap stabil.
  /// Ini mencegah UI "flicker" akibat noise sensor.
  static const int kDebounceFrames = 5;

  /// Label default jika model belum mengenali isyarat.
  static const String kDetecting = 'Mendeteksi...';

  // ───── State Internal ────────────────────────────────────────────────────────

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isLoaded = false;

  /// Parameter StandardScaler — diinisialisasi dari scaler JSON.
  /// mean  : rata-rata tiap fitur dari dataset training
  /// scale : standar deviasi tiap fitur dari dataset training
  List<double> currentMean = [];
  List<double> currentScale = [];

  // Debounce buffer: menyimpan N prediksi frame terakhir
  final List<String> _debounceBuffer = [];
  String _lastStableLabel = '';

  // ───── Getters ───────────────────────────────────────────────────────────────

  bool get isModelLoaded => _isLoaded;

  // ─────────────────────────────────────────────────────────────────────────────
  //  1. LOAD MODEL & SCALER
  // ─────────────────────────────────────────────────────────────────────────────

  /// Inisialisasi: muat TFLite model, labels, dan scaler params.
  ///
  /// Panggil sekali saat aplikasi pertama kali dimuat (contoh: di initState
  /// atau di constructor Provider).
  Future<void> init() async {
    try {
      // ── Load labels (a-z) ──────────────────────────────────────────────────
      final labelsStr = await rootBundle.loadString('assets/nn_labels.json');
      final dynamic decoded = jsonDecode(labelsStr);
      final List<dynamic> rawLabels = decoded is List
          ? decoded
          : (decoded as Map<String, dynamic>)['labels'] as List<dynamic>;
      _labels = rawLabels.map((e) => e.toString().toUpperCase()).toList();
      _log('✅ [PredictionService] Labels (${_labels.length}): $_labels');

      // ── Load scaler params ─────────────────────────────────────────────────
      // Format JSON: { "min": [33 nilai], "max": [33 nilai] }
      await _loadScaler();

      // ── Load TFLite interpreter ────────────────────────────────────────────
      _log('⏳ [PredictionService] Loading model...');
      _interpreter = await Interpreter.fromAsset(
        'assets/sibi_model_new.tflite',
      );
      _isLoaded = true;

      _log('✅ [PredictionService] Model siap!');
      _log('   Input  : ${_interpreter!.getInputTensors().first.shape}');
      _log('   Output : ${_interpreter!.getOutputTensors().first.shape}');
    } catch (e) {
      _isLoaded = false;
      print('❌ [PredictionService] init() gagal: $e');
    }
  }

  Future<void> _loadScaler() async {
    final scalerStr = await rootBundle.loadString(
      'assets/scaler_params_standard.json',
    );
    final Map<String, dynamic> scalerData = jsonDecode(scalerStr);

    currentMean = (scalerData['mean'] as List)
        .map((e) => (e as num).toDouble())
        .toList();
    currentScale = (scalerData['scale'] as List)
        .map((e) => (e as num).toDouble())
        .toList();

    if (currentMean.length != kFeatureCount ||
        currentScale.length != kFeatureCount) {
      throw Exception(
        'Scaler mismatch! Expected $kFeatureCount fitur, '
        'got mean=${currentMean.length} scale=${currentScale.length}.',
      );
    }
    _log(
      '✅ [PredictionService] StandardScaler: ${currentMean.length} fitur loaded.',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  2. STATE KALIBRASI DINAMIS
  // ─────────────────────────────────────────────────────────────────────────────

  /// Update mean kalibrasi secara dinamis (opsional, advanced use).
  void calibrateMean(List<double> sensorData) {
    if (sensorData.length != kFeatureCount) {
      print(
        '❌ [PredictionService] calibrateMean: panjang data harus $kFeatureCount '
        '(dapat ${sensorData.length})',
      );
      return;
    }
    currentMean = List.from(sensorData);
    _log('🔄 [PredictionService] currentMean diperbarui.');
  }

  /// Update scale kalibrasi secara dinamis (opsional, advanced use).
  void calibrateScale(List<double> sensorData) {
    if (sensorData.length != kFeatureCount) {
      print(
        '❌ [PredictionService] calibrateScale: panjang data harus $kFeatureCount '
        '(dapat ${sensorData.length})',
      );
      return;
    }
    currentScale = List.from(sensorData);
    _log('🔄 [PredictionService] currentScale diperbarui.');
  }

  /// Reset kalibrasi ke nilai default dari scaler_params_standard.json.
  Future<void> resetCalibration() async {
    await _loadScaler();
    _log('🔄 [PredictionService] Kalibrasi di-reset ke nilai default.');
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  3. PREPROCESSING — MinMax Normalization
  // ─────────────────────────────────────────────────────────────────────────────

  /// Normalisasi data sensor menggunakan StandardScaler:
  ///   `normalized = (raw - mean) / scale`
  ///
  /// - Konsisten dengan preprocessing saat training model.
  /// - Tidak ada clamping karena StandardScaler tidak bounded.
  List<double> normalize(List<double> rawData) {
    final result = List<double>.generate(kFeatureCount, (i) {
      final scale = currentScale[i];
      // Guard: pembagian dengan nol
      if (scale == 0.0) return 0.0;
      return (rawData[i] - currentMean[i]) / scale;
    });

    _log(
      '📊 [PredictionService] StandardScaled: '
      '${result.map((e) => e.toStringAsFixed(3)).take(5).join(', ')}...',
    );
    return result;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  4. INFERENCE & DECISION
  // ─────────────────────────────────────────────────────────────────────────────

  /// Titik masuk utama. Panggil ini dari Stream Bluetooth setiap kali
  /// ada data sensor baru (33 fitur, SUDAH tanpa timestamp).
  ///
  /// Return [PredictionResult] dengan:
  ///   - `label` → huruf stabil (A-Z) atau '' jika belum stabil
  ///   - `confidence` → probabilitas softmax [0-1]
  ///   - `displayStatus` → string siap tampil di UI
  PredictionResult predict(List<double> rawFeatures) {
    // ── Guard: model belum siap ──────────────────────────────────────────────
    if (!_isLoaded || _interpreter == null) {
      return PredictionResult.loading;
    }

    // ── Guard: jumlah fitur ──────────────────────────────────────────────────
    if (rawFeatures.length < kFeatureCount) {
      _log(
        '⚠️  [PredictionService] Fitur kurang: '
        '${rawFeatures.length}/$kFeatureCount',
      );
      return PredictionResult.empty;
    }

    // ── Guard: NaN / Inf ────────────────────────────────────────────────────
    if (rawFeatures.any((v) => v.isNaN || v.isInfinite)) {
      print('❌ [PredictionService] Input mengandung NaN/Inf!');
      return PredictionResult.empty;
    }

    try {
      // Step 1: Ambil 33 fitur pertama (antisipasi data lebih panjang)
      final features = rawFeatures.take(kFeatureCount).toList();

      // Step 2: Normalisasi MinMax
      final normalized = normalize(features);
      _log(
        '📊 [PredictionService] Normalized: '
        '${normalized.map((e) => e.toStringAsFixed(2)).join(', ')}',
      );

      // Step 3: Inference TFLite
      //   Input tensor  : shape [1, 33]
      //   Output tensor : shape [1, nLabels]
      final input = [normalized];
      final output = List.generate(1, (_) => List.filled(_labels.length, 0.0));
      _interpreter!.run(input, output);

      final scores = output[0]; // List<double> panjang nLabels

      // Step 4: Build allScores map untuk keperluan debug
      final allScores = <String, double>{
        for (int i = 0; i < scores.length; i++)
          (i < _labels.length ? _labels[i] : '$i'): scores[i],
      };

      // Step 5: Argmax — temukan label dengan skor tertinggi
      int bestIdx = 0;
      double bestScore = scores[0];
      for (int i = 1; i < scores.length; i++) {
        if (scores[i] > bestScore) {
          bestScore = scores[i];
          bestIdx = i;
        }
      }

      _log(
        '📈 [PredictionService] Best → '
        '${_labels[bestIdx]} (${(bestScore * 100).toStringAsFixed(1)}%)',
      );

      // Step 6: Confidence threshold
      if (bestScore < kConfidenceThreshold) {
        _log(
          '⚠️  [PredictionService] Confidence ${(bestScore * 100).toStringAsFixed(1)}% '
          '< ${(kConfidenceThreshold * 100).toStringAsFixed(0)}% → kDetecting',
        );
        _pushDebounce(''); // Frame tidak valid → reset streak
        return PredictionResult(
          label: '',
          confidence: bestScore,
          allScores: allScores,
          displayStatus: kDetecting,
        );
      }

      // Step 7: Debounce / Stability check
      final rawLabel = bestIdx < _labels.length ? _labels[bestIdx] : '?';
      final stableLabel = _pushDebounce(rawLabel);

      return PredictionResult(
        label: stableLabel, // Kosong jika belum stabil
        confidence: bestScore,
        allScores: allScores,
        displayStatus: stableLabel.isNotEmpty ? stableLabel : kDetecting,
      );
    } catch (e, st) {
      print('❌ [PredictionService] predict() error: $e\n$st');
      return PredictionResult.empty;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  5. STABILITY CONTROL — Debouncing
  // ─────────────────────────────────────────────────────────────────────────────

  /// Push satu prediksi frame ke buffer debounce.
  ///
  /// Return label jika frame yang SAMA sudah muncul [kDebounceFrames] kali
  /// berturut-turut, atau string kosong jika belum stabil.
  String _pushDebounce(String rawLabel) {
    _debounceBuffer.add(rawLabel);

    // Jaga buffer tetap di ukuran maksimum
    if (_debounceBuffer.length > kDebounceFrames) {
      _debounceBuffer.removeAt(0);
    }

    // Semua elemen buffer harus sama DAN bukan string kosong
    final isStable =
        _debounceBuffer.length == kDebounceFrames &&
        rawLabel.isNotEmpty &&
        _debounceBuffer.every((l) => l == rawLabel);

    if (isStable) {
      if (_lastStableLabel != rawLabel) {
        _lastStableLabel = rawLabel;
        print('✅ [PredictionService] STABLE OUTPUT: $rawLabel');
      }
      return rawLabel;
    }

    return '';
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  UTILITIES
  // ─────────────────────────────────────────────────────────────────────────────

  /// Reset debounce buffer dan stable label — panggil saat koneksi BLE terputus
  /// atau saat pengguna menekan tombol "Reset".
  void reset() {
    _debounceBuffer.clear();
    _lastStableLabel = '';
    _log('🔄 [PredictionService] Debounce reset.');
  }

  void dispose() {
    _interpreter?.close();
    _isLoaded = false;
    _debounceBuffer.clear();
  }

  static const bool _debugMode = true;
  void _log(String msg) {
    if (_debugMode) print(msg);
  }
}
