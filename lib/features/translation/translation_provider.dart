import 'package:flutter/material.dart';
import 'controllers/gesture_controller.dart';
import 'tts_service.dart';

class TranslationProvider with ChangeNotifier {
  late GestureController _gestureController;
  final TTSService _ttsService = TTSService();

  String _translatedText = "";
  bool _isTTSEnabled = true;
  double _confidenceScore = 0.0;
  bool _isModelLoaded = false;

  TranslationProvider() {
    _gestureController = GestureController();
    _init();
  }

  Future<void> _init() async {
    await _gestureController.init();
    _isModelLoaded = _gestureController.isModelLoaded;
    notifyListeners();
    _ttsService.init();
  }

  // Getters
  String get translatedText => _translatedText;
  bool get isTTSEnabled => _isTTSEnabled;
  double get confidenceScore => _confidenceScore;
  bool get isModelLoaded => _isModelLoaded;

  String get confidencePercent =>
      '${(_confidenceScore * 100).toStringAsFixed(1)}%';

  void toggleTTS(bool enabled) {
    _isTTSEnabled = enabled;
    notifyListeners();
  }

  void updateData(List<double> data) {
    if (data.isEmpty) return;

    // ✅ Timestamp sudah di-strip oleh BLEService.dart (sublist(1, 34))
    // Di sini data yang masuk SUDAH 33 fitur murni — tidak perlu strip lagi.
    final List<double> mlFeatures = data;

    // Guard: wajib 33 fitur
    if (mlFeatures.length != 33) {
      return;
    }

    // Jalankan pipeline terpadu (Filter -> Prediction -> Majority Voting)
    final (finalLabel, finalConf) = _gestureController.processSensorData(mlFeatures);

    if (finalLabel.isEmpty) return;

    // Update UI — confidence sekarang real dari model, bukan hardcoded
    if (_translatedText != finalLabel || (_confidenceScore - finalConf).abs() > 0.01) {
      _translatedText = finalLabel;
      _confidenceScore = finalConf;
      notifyListeners();

      if (_isTTSEnabled && _translatedText.isNotEmpty) {
        _ttsService.speak(_translatedText);
      }
    }
  }

  void clearText() {
    _translatedText = "";
    _confidenceScore = 0.0;
    _gestureController.reset();
    notifyListeners();
  }

  /// Reset filter & voting state tanpa hapus teks — dipakai oleh dummy test buttons
  /// agar state EMA dari gesture sebelumnya tidak bercampur dengan gesture baru.
  void resetController() {
    _gestureController.reset();
  }
}
