import 'package:flutter_tts/flutter_tts.dart';

class TTSService {
  final FlutterTts _flutterTts = FlutterTts();

  // ✅ PERBAIKAN: Throttle TTS — suara hanya boleh keluar 1x per 2.5 detik
  // Mencegah TTS "spam" saat prediksi berubah-ubah akibat jitter sensor
  DateTime? _lastSpokenTime;
  String _lastSpokenText = '';
  static const _cooldownDuration = Duration(milliseconds: 2500);

  Future<void> init() async {
    await _flutterTts.setLanguage("id-ID");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;

    final now = DateTime.now();

    // Cek apakah teks sama persis dengan yang baru diucapkan
    final bool isSameText = text == _lastSpokenText;

    // Cek apakah masih dalam periode cooldown
    final bool isInCooldown = _lastSpokenTime != null &&
        now.difference(_lastSpokenTime!) < _cooldownDuration;

    // Lewati jika: teks sama DAN masih dalam cooldown
    if (isSameText && isInCooldown) return;

    // Jika teks BEDA, boleh langsung bicara (huruf baru terdeteksi)
    // Jika teks SAMA tapi cooldown sudah habis, boleh ulang bicara
    _lastSpokenText = text;
    _lastSpokenTime = now;
    await _flutterTts.speak(text);
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }
}
