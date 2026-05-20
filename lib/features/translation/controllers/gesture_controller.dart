import '../services/prediction_service.dart';

/// GestureController
///
/// Layer tipis antara [TranslationProvider] dan [PredictionService].
///
/// Cara pakai:
/// ```dart
/// await _gestureController.init();
/// final (label, conf) = _gestureController.processSensorData(raw33);
/// if (label.isNotEmpty) updateUI(label, conf);
/// ```
class GestureController {
  final PredictionService _service = PredictionService();

  bool get isModelLoaded => _service.isModelLoaded;

  /// Muat model. Panggil sekali di awal.
  Future<void> init() async => _service.init();

  /// Proses 1 frame sensor (33 fitur raw, tanpa timestamp).
  ///
  /// Secara internal: konversi quaternion → Euler ZYX, susun 24 fitur,
  /// inference TFLite, debounce.
  ///
  /// Return (label, confidence):
  ///   - label = huruf stabil (A-Z) atau '' jika belum stabil
  ///   - confidence = probabilitas [0.0 – 1.0]
  (String, double) processSensorData(List<double> rawData) {
    if (rawData.length != PredictionService.kRawFeatureCount) {
      return ('', 0.0);
    }
    final result = _service.predict(rawData);
    return (result.label, result.confidence);
  }

  /// Reset debounce buffer — panggil saat BLE disconnect atau gesture baru.
  void reset() => _service.reset();

  void dispose() => _service.dispose();
}
