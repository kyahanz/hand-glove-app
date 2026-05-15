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
  static const double kConfidenceThreshold = 0.85;

  /// Jumlah frame berturut-turut dengan huruf SAMA agar output dianggap stabil.
  /// Ini mencegah UI "flicker" akibat noise sensor.
  static const int kDebounceFrames = 5;

  /// Label default jika model belum mengenali isyarat.
  static const String kDetecting = 'Mendeteksi...';

  // ───── State Internal ────────────────────────────────────────────────────────

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isLoaded = false;

  /// Nilai kalibrasi aktif — diinisialisasi dari scaler JSON,
  /// bisa diubah dinamis via [calibrateMin] / [calibrateMax].
  List<double> currentMin = [];
  List<double> currentMax = [];

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
      final labelsStr =
          await rootBundle.loadString('assets/nn_labels.json');
      final List<dynamic> rawLabels = jsonDecode(labelsStr);
      _labels = rawLabels.map((e) => e.toString().toUpperCase()).toList();
      _log('✅ [PredictionService] Labels (${_labels.length}): $_labels');

      // ── Load scaler params ─────────────────────────────────────────────────
      // Format JSON: { "min": [33 nilai], "max": [33 nilai] }
      await _loadScaler();

      // ── Load TFLite interpreter ────────────────────────────────────────────
      _log('⏳ [PredictionService] Loading model...');
      _interpreter = await Interpreter.fromAsset(
        'assets/glove_model_robust.tflite',
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
    final scalerStr =
        await rootBundle.loadString('assets/scaler_params_robust.json');
    final Map<String, dynamic> scalerData = jsonDecode(scalerStr);

    currentMin = (scalerData['min'] as List)
        .map((e) => (e as num).toDouble())
        .toList();
    currentMax = (scalerData['max'] as List)
        .map((e) => (e as num).toDouble())
        .toList();

    if (currentMin.length != kFeatureCount ||
        currentMax.length != kFeatureCount) {
      throw Exception(
        'Scaler mismatch! Expected $kFeatureCount fitur, '
        'got min=${currentMin.length} max=${currentMax.length}.',
      );
    }
    _log('✅ [PredictionService] Scaler: ${currentMin.length} fitur loaded.');
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  2. STATE KALIBRASI DINAMIS
  // ─────────────────────────────────────────────────────────────────────────────

  /// Update nilai minimum kalibrasi secara dinamis.
  ///
  /// Gunakan ini untuk menyesuaikan sarung tangan tiap pengguna:
  ///
  /// ```dart
  /// // Contoh: ambil 30 sample saat tangan dalam posisi rileks
  /// predictionService.calibrateMin(sensorSample30Values);
  /// ```
  ///
  /// [sensorData] harus berisi tepat [kFeatureCount] (33) nilai.
  void calibrateMin(List<double> sensorData) {
    if (sensorData.length != kFeatureCount) {
      print('❌ [PredictionService] calibrateMin: panjang data harus $kFeatureCount '
          '(dapat ${sensorData.length})');
      return;
    }
    currentMin = List.from(sensorData);
    _log('🔄 [PredictionService] currentMin diperbarui.');
  }

  /// Update nilai maksimum kalibrasi secara dinamis.
  ///
  /// ```dart
  /// // Contoh: ambil sample saat semua jari dalam posisi menekuk penuh
  /// predictionService.calibrateMax(sensorSampleFullBend);
  /// ```
  void calibrateMax(List<double> sensorData) {
    if (sensorData.length != kFeatureCount) {
      print('❌ [PredictionService] calibrateMax: panjang data harus $kFeatureCount '
          '(dapat ${sensorData.length})');
      return;
    }
    currentMax = List.from(sensorData);
    _log('🔄 [PredictionService] currentMax diperbarui.');
  }

  /// Reset kalibrasi ke nilai default dari scaler_params_robust.json.
  Future<void> resetCalibration() async {
    await _loadScaler();
    _log('🔄 [PredictionService] Kalibrasi di-reset ke nilai default.');
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  3. PREPROCESSING — MinMax Normalization
  // ─────────────────────────────────────────────────────────────────────────────

  /// Normalisasi data sensor menggunakan rumus MinMax:
  ///   `normalized = (raw - currentMin) / (currentMax - currentMin)`
  ///
  /// - Hasil di-clamp ke [0.0, 1.0].
  /// - Jika `(currentMax - currentMin) == 0` (range nol), nilai jadi 0.0.
  ///
  /// Fungsi ini bisa dipanggil mandiri untuk keperluan debug:
  /// ```dart
  /// final normed = service.normalize(rawSensor33);
  /// print(normed); // [0.12, 0.87, ...]
  /// ```
  List<double> normalize(List<double> rawData) {
    bool anyOutOfRange = false;

    final result = List<double>.generate(kFeatureCount, (i) {
      final min = currentMin[i];
      final max = currentMax[i];
      final range = max - min;

      // Guard: pembagian dengan nol
      if (range == 0.0) return 0.0;

      final norm = (rawData[i] - min) / range;
      if (norm < 0.0 || norm > 1.0) anyOutOfRange = true;
      return norm.clamp(0.0, 1.0);
    });

    if (anyOutOfRange) {
      _log('⚠️  [PredictionService] Beberapa nilai sensor di luar range '
          'training (calibration drift?). Pertimbangkan panggil calibrateMin/Max().');
    }
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
      _log('⚠️  [PredictionService] Fitur kurang: '
          '${rawFeatures.length}/$kFeatureCount');
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
      _log('📊 [PredictionService] Normalized: '
          '${normalized.map((e) => e.toStringAsFixed(2)).join(', ')}');

      // Step 3: Inference TFLite
      //   Input tensor  : shape [1, 33]
      //   Output tensor : shape [1, nLabels]
      final input = [normalized];
      final output =
          List.generate(1, (_) => List.filled(_labels.length, 0.0));
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

      _log('📈 [PredictionService] Best → '
          '${_labels[bestIdx]} (${(bestScore * 100).toStringAsFixed(1)}%)');

      // Step 6: Confidence threshold
      if (bestScore < kConfidenceThreshold) {
        _log('⚠️  [PredictionService] Confidence ${(bestScore * 100).toStringAsFixed(1)}% '
            '< ${(kConfidenceThreshold * 100).toStringAsFixed(0)}% → kDetecting');
        _pushDebounce(''); // Frame tidak valid → reset streak
        return PredictionResult(
          label: '',
          confidence: bestScore,
          allScores: allScores,
          displayStatus: kDetecting,
        );
      }

      // Step 7: Debounce / Stability check
      final rawLabel =
          bestIdx < _labels.length ? _labels[bestIdx] : '?';
      final stableLabel = _pushDebounce(rawLabel);

      return PredictionResult(
        label: stableLabel,           // Kosong jika belum stabil
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
    final isStable = _debounceBuffer.length == kDebounceFrames &&
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
