import '../services/prediction_service.dart';

/// GestureController
///
/// Layer tipis antara [TranslationProvider] dan [PredictionService].
/// Semua logika berat (normalisasi, inference, debounce) ada di [PredictionService].
///
/// Cara pakai dari TranslationProvider:
/// ```dart
/// // Inisialisasi (sekali)
/// await _gestureController.init();
///
/// // Setiap ada data baru dari BLE Stream (33 fitur, TANPA timestamp):
/// final (label, conf) = _gestureController.processSensorData(features33);
/// if (label.isNotEmpty) {
///   // Huruf sudah stabil dan confidence >= 85%
///   updateUI(label, conf);
/// }
/// ```
class GestureController {
  final PredictionService _service = PredictionService();

  bool get isModelLoaded => _service.isModelLoaded;

  /// Muat model + scaler. Panggil sekali di awal.
  Future<void> init() async {
    await _service.init();
  }

  /// Proses 1 frame sensor (33 fitur murni, SUDAH tanpa timestamp).
  ///
  /// Return `(label, confidence)`:
  ///   - label = huruf stabil (A-Z) atau '' jika belum stabil
  ///   - confidence = probabilitas [0.0 – 1.0]
  (String, double) processSensorData(List<double> rawData) {
    if (rawData.length != PredictionService.kFeatureCount) {
      return ('', 0.0);
    }
    final result = _service.predict(rawData);
    return (result.label, result.confidence);
  }

  // ── Akses langsung ke PredictionService (untuk kalibrasi dari UI) ──────────

  /// ✅ FIX: Update mean kalibrasi (StandardScaler — bukan MinMax lagi).
  /// Panggil saat ingin adaptasi scaler ke pengguna baru.
  void calibrateMean(List<double> sensorData) =>
      _service.calibrateMean(sensorData);

  /// ✅ FIX: Update scale/std kalibrasi (StandardScaler — bukan MinMax lagi).
  void calibrateScale(List<double> sensorData) =>
      _service.calibrateScale(sensorData);

  /// Reset kalibrasi ke nilai default dari scaler_params_standard.json.
  Future<void> resetCalibration() => _service.resetCalibration();

  /// Reset debounce buffer — panggil saat BLE disconnect atau gesture baru.
  void reset() => _service.reset();

  void dispose() => _service.dispose();
}
