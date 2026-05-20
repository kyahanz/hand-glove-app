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
  bool _isSuccess = false;
  Timer? _successTimer;

  @override
  void dispose() {
    _successTimer?.cancel();
    super.dispose();
  }

  void _checkGesture(String predicted, double confidence) {
    if (_isSuccess) return;
    final bool isMatch = predicted.toUpperCase() == widget.target.toUpperCase();
    if (isMatch && confidence >= 0.65) {
      _successTimer ??= Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _isSuccess = true);
      });
    } else {
      _successTimer?.cancel();
      _successTimer = null;
    }
  }

  void _reset() {
    _successTimer?.cancel();
    setState(() {
      _isSuccess = false;
    });
    context.read<TranslationProvider>().clearText();
  }

  @override
  Widget build(BuildContext context) {
    final ble = Provider.of<BLEProvider>(context);
    final trans = Provider.of<TranslationProvider>(context);

    final bool isConnected =
        ble.connectionState == BluetoothConnectionState.connected ||
            ble.isMockMode;
    final String predicted = trans.translatedText;
    final double confidence = trans.confidenceScore;
    final bool isMatch = predicted.isNotEmpty &&
        predicted.toUpperCase() == widget.target.toUpperCase();

    if (isConnected && predicted.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkGesture(predicted, confidence);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Latihan: ${widget.target}"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_isSuccess)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: "Ulangi",
              onPressed: _reset,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          children: [
            // ── Target letter card ──────────────────────────────────────
            _TargetCard(
              letter: widget.target,
              isMatch: isMatch,
              isSuccess: _isSuccess,
            ),
            const SizedBox(height: 20),

            // ── BLE connection area (tampil jika belum konek) ───────────
            if (!isConnected) ...[
              _ConnectSection(ble: ble),
              const SizedBox(height: 20),
            ],

            // ── Practice feedback (tampil jika sudah konek) ────────────
            if (isConnected) ...[
              _isSuccess
                  ? _SuccessCard(onRetry: _reset, onBack: () => Navigator.pop(context))
                  : _AccuracyCard(
                      predicted: predicted,
                      confidence: confidence,
                      isMatch: isMatch,
                    ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Widgets ─────────────────────────────────────────────────────────────────

class _TargetCard extends StatelessWidget {
  final String letter;
  final bool isMatch;
  final bool isSuccess;

  const _TargetCard({
    required this.letter,
    required this.isMatch,
    required this.isSuccess,
  });

  @override
  Widget build(BuildContext context) {
    final Color borderColor = isSuccess
        ? Colors.greenAccent
        : isMatch
            ? AppTheme.primaryColor
            : Colors.white10;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: (isMatch || isSuccess)
            ? [
                BoxShadow(
                  color: borderColor.withOpacity(0.25),
                  blurRadius: 32,
                  spreadRadius: 2,
                )
              ]
            : [],
      ),
      child: Column(
        children: [
          Text(
            letter,
            style: TextStyle(
              fontSize: 120,
              fontWeight: FontWeight.w900,
              color: isSuccess
                  ? Colors.greenAccent
                  : isMatch
                      ? AppTheme.primaryColor
                      : Colors.white,
              height: 1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Lakukan isyarat huruf ini",
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectSection extends StatelessWidget {
  final BLEProvider ble;
  const _ConnectSection({required this.ble});

  @override
  Widget build(BuildContext context) {
    if (ble.isScanning) {
      return _tile(
        child: Column(
          children: [
            const CircularProgressIndicator(color: AppTheme.primaryColor),
            const SizedBox(height: 12),
            const Text("Mencari sarung tangan...",
                style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: ble.stopScan,
              child: const Text("Berhenti",
                  style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );
    }

    if (ble.isConnecting) {
      return _tile(
        child: const Column(
          children: [
            CircularProgressIndicator(color: AppTheme.primaryColor),
            SizedBox(height: 12),
            Text("Menghubungkan...",
                style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    if (ble.scanResults.isNotEmpty) {
      return Column(
        children: ble.scanResults.map((result) {
          String name = result.device.platformName;
          if (name.isEmpty) name = result.advertisementData.advName;
          if (name.isEmpty) name = "Perangkat Tidak Dikenal";
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: ListTile(
              leading:
                  const Icon(Icons.bluetooth, color: AppTheme.primaryColor),
              title: Text(name,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text(result.device.remoteId.toString(),
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 11)),
              trailing: ElevatedButton(
                onPressed: () => ble.connect(result.device),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  textStyle: const TextStyle(fontSize: 13),
                ),
                child: const Text("Hubungkan"),
              ),
            ),
          );
        }).toList(),
      );
    }

    // Default: belum scan
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.bluetooth_disabled, color: Colors.orange),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Sarung tangan belum terhubung.\nHubungkan untuk mulai latihan.",
                  style: TextStyle(color: Colors.orange, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: ble.startScan,
            icon: const Icon(Icons.bluetooth_searching),
            label: const Text("Cari Sarung Tangan"),
          ),
        ),
      ],
    );
  }

  Widget _tile({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }
}

class _AccuracyCard extends StatelessWidget {
  final String predicted;
  final double confidence;
  final bool isMatch;

  const _AccuracyCard({
    required this.predicted,
    required this.confidence,
    required this.isMatch,
  });

  @override
  Widget build(BuildContext context) {
    final double displayConf = isMatch ? confidence : 0.0;
    final Color activeColor =
        displayConf > 0.8 ? Colors.greenAccent : AppTheme.primaryColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          // Detected letter
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Terdeteksi: ",
                  style: TextStyle(color: Colors.white54, fontSize: 16)),
              Text(
                predicted.isEmpty ? "—" : predicted,
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  color: isMatch ? Colors.greenAccent : Colors.orangeAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Progress bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Akurasi",
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
              Text(
                "${(displayConf * 100).toStringAsFixed(0)}%",
                style: TextStyle(
                  color: activeColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: displayConf,
              backgroundColor: Colors.white10,
              color: activeColor,
              minHeight: 14,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isMatch
                ? "Tahan 2 detik untuk menyelesaikan latihan"
                : predicted.isEmpty
                    ? "Lakukan isyarat dengan sarung tangan"
                    : "Belum cocok, coba lagi",
            style: TextStyle(
              color: isMatch
                  ? Colors.greenAccent.withOpacity(0.6)
                  : Colors.white24,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onBack;

  const _SuccessCard({required this.onRetry, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return FadeInUp(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withOpacity(0.07),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.greenAccent, size: 72),
            const SizedBox(height: 12),
            const Text(
              "Luar Biasa!",
              style: TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
                fontSize: 26,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Gerakan kamu sudah benar",
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onRetry,
                    style: OutlinedButton.styleFrom(
                      side:
                          const BorderSide(color: AppTheme.primaryColor),
                      foregroundColor: AppTheme.primaryColor,
                    ),
                    child: const Text("Ulangi"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onBack,
                    child: const Text("Selesai"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
