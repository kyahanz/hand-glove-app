import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  PredictionResult
// ─────────────────────────────────────────────────────────────────────────────
class PredictionResult {
  final String label;
  final double confidence;
  final Map<String, double> allScores;
  final String displayStatus;

  const PredictionResult({
    required this.label,
    required this.confidence,
    required this.allScores,
    required this.displayStatus,
  });

  static const PredictionResult empty = PredictionResult(
    label: '', confidence: 0.0, allScores: {}, displayStatus: 'Mendeteksi...',
  );
  static const PredictionResult loading = PredictionResult(
    label: '', confidence: 0.0, allScores: {}, displayStatus: 'Memuat Model...',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  PredictionService
//
//  Pipeline (identik dengan MATLAB + Python training):
//    1. Terima 33 fitur raw dari BLE (tanpa timestamp)
//    2. Ekstrak quaternion per jari → konversi ke Euler ZYX (derajat)
//    3. Susun 24 fitur: [dip, pip, Q_z, Q_y, Q_x] per jari
//    4. Feed langsung ke TFLite (tanpa scaler)
//    5. Confidence threshold + debounce → output stabil
//
//  Raw 33 fitur (setelah strip timestamp di BLEService):
//    [0-3]   hand_w/x/y/z          ← tidak dipakai
//    [4-7]   pinky_mcp_w/x/y/z
//    [8-11]  ring_mcp_w/x/y/z
//    [12-15] middle_mcp_w/x/y/z
//    [16-19] index_mcp_w/x/y/z
//    [20-23] thumb_mcp_w/x/y/z
//    [24]    pinky_pip
//    [25]    ring_pip
//    [26]    middle_pip
//    [27]    index_pip
//    [28]    thumb_ip
//    [29]    pinky_dip
//    [30]    ring_dip
//    [31]    middle_dip
//    [32]    index_dip
//
//  24 fitur ke model (urutan identik MATLAB cols):
//    index_dip,  index_pip,  indexQ_z,  indexQ_y,  indexQ_x   [0-4]
//    middle_dip, middle_pip, middleQ_z, middleQ_y, middleQ_x  [5-9]
//    ring_dip,   ring_pip,   ringQ_z,   ringQ_y,   ringQ_x    [10-14]
//    pinky_dip,  pinky_pip,  pinkyQ_z,  pinkyQ_y,  pinkyQ_x   [15-19]
//    thumb_ip,   thumbQ_z,   thumbQ_y,  thumbQ_x               [20-23]
// ─────────────────────────────────────────────────────────────────────────────
class PredictionService {

  /// Fitur raw dari BLE (33, tanpa timestamp)
  static const int kRawFeatureCount = 33;

  /// Fitur input ke model setelah konversi Euler (24)
  static const int kModelFeatureCount = 24;

  /// Threshold confidence minimum
  static const double kConfidenceThreshold = 0.35; // ← ubah nilai ini

  /// Frame berturut-turut harus sama agar prediksi dianggap stabil
  static const int kDebounceFrames = 5;

  static const String kDetecting = 'Mendeteksi...';

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isLoaded = false;

  final List<String> _debounceBuffer = [];
  String _lastStableLabel = '';

  bool get isModelLoaded => _isLoaded;

  // ── 1. INIT ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    try {
      // ── Load labels ────────────────────────────────────────────────────────
      _log('⏳ Loading labels...');
      final labelsStr = await rootBundle.loadString('assets/nn_labels.json');
      final dynamic decoded = jsonDecode(labelsStr);
      final List<dynamic> rawLabels =
          decoded is List ? decoded : (decoded as Map)['labels'] as List;
      _labels = rawLabels.map((e) => e.toString().toUpperCase()).toList();
      _log('✅ Labels (${_labels.length}): $_labels');

      // ── Load TFLite model ─────────────────────────────────────────────────
      _log('⏳ Loading model...');
      _interpreter = await Interpreter.fromAsset('assets/glove_model_robust.tflite');

      // ── Validasi shape input model ─────────────────────────────────────────
      final inputShape  = _interpreter!.getInputTensors().first.shape;
      final outputShape = _interpreter!.getOutputTensors().first.shape;
      _log('   Input  shape : $inputShape');
      _log('   Output shape : $outputShape');

      // Pastikan model menerima 24 fitur (bukan 33 format lama)
      if (inputShape.length < 2 || inputShape[1] != kModelFeatureCount) {
        throw Exception(
          'Model input shape $inputShape tidak sesuai. '
          'Dibutuhkan [1, $kModelFeatureCount]. '
          'Pastikan model dari Colab (24 fitur Euler) sudah di-copy ke assets/.',
        );
      }

      _isLoaded = true;
      _log('✅ Model siap! Input=$inputShape Output=$outputShape');
    } catch (e) {
      _isLoaded = false;
      print('❌ [PredictionService] init() GAGAL: $e');
    }
  }

  // ── 2. QUATERNION → EULER ZYX (derajat) ─────────────────────────────────────
  //
  // Identik dengan MATLAB: rad2deg(quat2eul(quaternion(w,x,y,z), 'ZYX'))
  // Output: [Z(yaw), Y(pitch), X(roll)] dalam derajat

  List<double> _quatToEulerZYX(double w, double x, double y, double z) {
    // Yaw (Z-axis)
    final double yaw = atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z));

    // Pitch (Y-axis) — clamp [-1, 1] untuk hindari domain error asin
    final double sinPitch = (2.0 * (w * y - z * x)).clamp(-1.0, 1.0);
    final double pitch = asin(sinPitch);

    // Roll (X-axis)
    final double roll = atan2(2.0 * (w * x + y * z), 1.0 - 2.0 * (x * x + y * y));

    const double rad2deg = 180.0 / pi;
    return [yaw * rad2deg, pitch * rad2deg, roll * rad2deg]; // [Z, Y, X]
  }

  // ── 3. BUILD 24 FITUR dari 33 raw BLE ────────────────────────────────────────

  List<double>? _buildFeatures(List<double> raw) {
    if (raw.length < kRawFeatureCount) return null;

    // Konjugat quaternion (w, x, y, z) → (w, -x, -y, -z) lalu konversi ke Euler ZYX
    // Konjugat dilakukan sebelum konversi, sesuai preprocessing saat training
    final indexQ  = _quatToEulerZYX(raw[16], -raw[17], -raw[18], -raw[19]);
    final middleQ = _quatToEulerZYX(raw[12], -raw[13], -raw[14], -raw[15]);
    final ringQ   = _quatToEulerZYX(raw[8],  -raw[9],  -raw[10], -raw[11]);
    final pinkyQ  = _quatToEulerZYX(raw[4],  -raw[5],  -raw[6],  -raw[7]);
    final thumbQ  = _quatToEulerZYX(raw[20], -raw[21], -raw[22], -raw[23]);

    // Susun 24 fitur (urutan IDENTIK dengan MATLAB cols dan Python FEATURE_COLS)
    return [
      // index:  dip,     pip,     Q_z,        Q_y,        Q_x
      raw[32], raw[27], indexQ[0],  indexQ[1],  indexQ[2],
      // middle: dip,     pip,     Q_z,        Q_y,        Q_x
      raw[31], raw[26], middleQ[0], middleQ[1], middleQ[2],
      // ring:   dip,     pip,     Q_z,        Q_y,        Q_x
      raw[30], raw[25], ringQ[0],   ringQ[1],   ringQ[2],
      // pinky:  dip,     pip,     Q_z,        Q_y,        Q_x
      raw[29], raw[24], pinkyQ[0],  pinkyQ[1],  pinkyQ[2],
      // thumb:  ip,      Q_z,        Q_y,        Q_x
      raw[28], thumbQ[0],  thumbQ[1],  thumbQ[2],
    ];
  }

  // ── 4. PREDICT ────────────────────────────────────────────────────────────────

  PredictionResult predict(List<double> rawFeatures) {
    if (!_isLoaded || _interpreter == null) return PredictionResult.loading;

    if (rawFeatures.length < kRawFeatureCount) {
      _log('⚠️ Fitur kurang: ${rawFeatures.length}/$kRawFeatureCount');
      return PredictionResult.empty;
    }

    if (rawFeatures.any((v) => v.isNaN || v.isInfinite)) {
      print('❌ Input NaN/Inf!');
      return PredictionResult.empty;
    }

    try {
      // Step 1: Bangun 24 fitur dari 33 raw (Euler + PIP/DIP)
      final features = _buildFeatures(rawFeatures);
      if (features == null) return PredictionResult.empty;

      _log('📊 Features (24): ${features.map((e) => e.toStringAsFixed(2)).join(', ')}');

      // Step 2: Inference — input [1,24], output [1,nLabels]
      final input  = [features];
      final output = List.generate(1, (_) => List.filled(_labels.length, 0.0));
      _interpreter!.run(input, output);

      final scores = output[0];

      // Step 3: Build allScores
      final allScores = <String, double>{
        for (int i = 0; i < scores.length; i++)
          (i < _labels.length ? _labels[i] : '$i'): scores[i],
      };

      // Step 4: Argmax
      int bestIdx = 0;
      double bestScore = scores[0];
      for (int i = 1; i < scores.length; i++) {
        if (scores[i] > bestScore) {
          bestScore = scores[i];
          bestIdx   = i;
        }
      }

      _log('📈 Best → ${_labels[bestIdx]} (${(bestScore * 100).toStringAsFixed(1)}%)');

      // Step 5: Confidence threshold
      if (bestScore < kConfidenceThreshold) {
        _log('⚠️ Confidence ${(bestScore * 100).toStringAsFixed(1)}%'
            ' < ${(kConfidenceThreshold * 100).toStringAsFixed(0)}% → detecting');
        _pushDebounce('');
        return PredictionResult(
          label: '', confidence: bestScore,
          allScores: allScores, displayStatus: kDetecting,
        );
      }

      // Step 6: Debounce
      final rawLabel    = bestIdx < _labels.length ? _labels[bestIdx] : '?';
      final stableLabel = _pushDebounce(rawLabel);

      return PredictionResult(
        label: stableLabel,
        confidence: bestScore,
        allScores: allScores,
        displayStatus: stableLabel.isNotEmpty ? stableLabel : kDetecting,
      );
    } catch (e, st) {
      print('❌ predict() error: $e\n$st');
      return PredictionResult.empty;
    }
  }

  // ── 5. DEBOUNCE ───────────────────────────────────────────────────────────────

  String _pushDebounce(String rawLabel) {
    _debounceBuffer.add(rawLabel);
    if (_debounceBuffer.length > kDebounceFrames) _debounceBuffer.removeAt(0);

    final isStable = _debounceBuffer.length == kDebounceFrames &&
        rawLabel.isNotEmpty &&
        _debounceBuffer.every((l) => l == rawLabel);

    if (isStable) {
      if (_lastStableLabel != rawLabel) {
        _lastStableLabel = rawLabel;
        print('✅ STABLE: $rawLabel');
      }
      return rawLabel;
    }
    return '';
  }

  void reset() {
    _debounceBuffer.clear();
    _lastStableLabel = '';
    _log('🔄 Debounce reset.');
  }

  void dispose() {
    _interpreter?.close();
    _isLoaded = false;
    _debounceBuffer.clear();
  }

  static const bool _debugMode = true;
  void _log(String msg) { if (_debugMode) print(msg); }
}
