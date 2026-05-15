
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'package:animate_do/animate_do.dart';
import '../../core/app_theme.dart';
import '../bluetooth/ble_provider.dart';
import '../translation/translation_provider.dart';

class PracticeScreen extends StatefulWidget {
  final String target;
  const PracticeScreen({super.key, required this.target});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  double _matchingProgress = 0.0;
  bool _isSuccess = false;
  Timer? _successTimer;

  // ✅ PERBAIKAN: Gunakan prediksi NYATA dari Neural Network (TranslationProvider)
  // Bandingkan label hasil prediksi AI dengan huruf target latihan.
  void _checkGesture(String predictedLabel, double confidence) {
    if (_isSuccess) return;

    final bool isMatch = predictedLabel.toUpperCase() == widget.target.toUpperCase();

    // Progress bar = confidence dari AI jika prediksinya cocok, 0 jika tidak
    final double newProgress = isMatch ? confidence.clamp(0.0, 1.0) : 0.0;

    setState(() {
      _matchingProgress = newProgress;
    });

    // Jika cocok dan confidence > 90%, mulai timer sukses
    if (isMatch && confidence > 0.9) {
      _startSuccessCounter();
    } else {
      _successTimer?.cancel();
      _successTimer = null;
    }
  }

  void _startSuccessCounter() {
    if (_successTimer != null) return;
    _successTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isSuccess = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _successTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bleProvider = Provider.of<BLEProvider>(context);

    // ✅ Ambil prediksi dari TranslationProvider (AI sesungguhnya)
    final translationProvider = Provider.of<TranslationProvider>(context);
    final String predictedLabel = translationProvider.translatedText;
    final double confidence = translationProvider.confidenceScore;

    // Trigger validasi setiap kali data berubah
    if (bleProvider.connectionState == BluetoothConnectionState.connected ||
        bleProvider.isMockMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (predictedLabel.isNotEmpty) {
          _checkGesture(predictedLabel, confidence);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Latihan: ${widget.target}"),
        backgroundColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // 1. Gesture Image Placeholder
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white10),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.front_hand_rounded,
                          size: 100, color: Colors.white24),
                      const SizedBox(height: 20),
                      Text(
                        "Lakukan Gerakan untuk '${widget.target}'",
                        style: const TextStyle(color: Colors.white54),
                      ),
                      const SizedBox(height: 8),
                      // Tampilkan prediksi AI real-time sebagai feedback
                      if (predictedLabel.isNotEmpty)
                        Text(
                          "AI mendeteksi: '$predictedLabel'",
                          style: TextStyle(
                            color: predictedLabel.toUpperCase() ==
                                    widget.target.toUpperCase()
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),

            // 2. Matching Progress
            _isSuccess
                ? FadeInUp(
                    child: Column(
                      children: [
                        const Icon(Icons.check_circle,
                            color: Colors.greenAccent, size: 80),
                        const SizedBox(height: 10),
                        const Text("Luar Biasa!",
                            style: TextStyle(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 24)),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Pelajaran Selanjutnya"),
                        )
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Text(
                        "Akurasi: ${(_matchingProgress * 100).toStringAsFixed(0)}%",
                        style: TextStyle(
                          color: _matchingProgress > 0.7
                              ? AppTheme.primaryColor
                              : Colors.white54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: _matchingProgress,
                        backgroundColor: Colors.white10,
                        color: _matchingProgress > 0.8
                            ? Colors.greenAccent
                            : AppTheme.primaryColor,
                        minHeight: 12,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Tahan gerakan selama 2 detik untuk selesai",
                        style: TextStyle(color: Colors.white24, fontSize: 12),
                      ),
                    ],
                  ),

            const SizedBox(height: 40),

            // Connection Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    bleProvider.connectionState ==
                                BluetoothConnectionState.connected ||
                            bleProvider.isMockMode
                        ? Icons.link
                        : Icons.link_off,
                    size: 16,
                    color: Colors.white38,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    bleProvider.connectionState ==
                                BluetoothConnectionState.connected ||
                            bleProvider.isMockMode
                        ? "Sarung Tangan Terhubung"
                        : "Sarung Tangan Terputus",
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
