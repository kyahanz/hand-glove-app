import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:animate_do/animate_do.dart';
import '../bluetooth/ble_provider.dart';
import '../translation/translation_provider.dart';
import '../../core/app_theme.dart';
import 'dummy_data.dart';

class TranslationScreen extends StatelessWidget {
  const TranslationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bleProvider = Provider.of<BLEProvider>(context);
    final translationProvider = Provider.of<TranslationProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Penerjemah"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // Model status indicator
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: translationProvider.isModelLoaded
                    ? Colors.green.withOpacity(0.2)
                    : Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: translationProvider.isModelLoaded
                      ? Colors.green.withOpacity(0.5)
                      : Colors.orange.withOpacity(0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    translationProvider.isModelLoaded
                        ? Icons.psychology
                        : Icons.psychology_outlined,
                    size: 14,
                    color: translationProvider.isModelLoaded
                        ? Colors.greenAccent
                        : Colors.orange,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    translationProvider.isModelLoaded ? "Neural Network" : "Fallback",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: translationProvider.isModelLoaded
                          ? Colors.greenAccent
                          : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Simulation Toggle
          Switch(
            value: bleProvider.isMockMode,
            onChanged: (value) => bleProvider.toggleMockMode(value),
            activeColor: AppTheme.primaryColor,
          ),
          const Center(child: Text("Sim   ", style: TextStyle(fontSize: 11))),
        ],
      ),
      body: Column(
        children: [
          // 1. Connection Status / Sensor Data Area
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: bleProvider.connectionState ==
                          BluetoothConnectionState.connected ||
                      bleProvider.isMockMode
                  ? _buildConnectedView(bleProvider)
                  : _buildScannerView(bleProvider, translationProvider),
            ),
          ),

          // 2. Translation Result Area
          Expanded(
            flex: 1,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(30, 20, 30, 20),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(40),
                  topRight: Radius.circular(40),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "HASIL TERJEMAHAN",
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          letterSpacing: 2,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      Row(
                        children: [
                          // Clear button
                          if (translationProvider.translatedText.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                              onPressed: () => translationProvider.clearText(),
                              tooltip: "Hapus",
                            ),
                          // TTS toggle
                          IconButton(
                            icon: Icon(
                              translationProvider.isTTSEnabled
                                  ? Icons.volume_up
                                  : Icons.volume_off,
                              color: AppTheme.primaryColor,
                            ),
                            onPressed: () => translationProvider
                                .toggleTTS(!translationProvider.isTTSEnabled),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Predicted letter (besar)
                  Expanded(
                    child: FadeInUp(
                      key: ValueKey(translationProvider.translatedText),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            translationProvider.translatedText.isEmpty
                                ? "—"
                                : translationProvider.translatedText,
                            style: const TextStyle(
                              fontSize: 72,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Status label bawah
                  Text(
                    translationProvider.translatedText.isEmpty
                        ? "Menunggu gerakan tangan..."
                        : "Terdeteksi",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugBtn(String label, TranslationProvider tp, BLEProvider provider) {
    return ElevatedButton(
      onPressed: () {
        // 1. Reset debounce & controller agar tidak tercampur gesture sebelumnya
        tp.resetController();

        // 2. Ambil samples 33-fitur dari DummyData (sudah tanpa timestamp)
        final List<List<double>> samples = DummyData.samples[label]!;

        // 3. Feed langsung ke pipeline (data sudah 33 fitur murni)
        for (int i = 0; i < samples.length; i++) {
          assert(samples[i].length == 33,
              'DummyData[$label][$i] harus 33 fitur, dapat ${samples[i].length}');
          if (i < 2) {
            print('🚀 DUMMY [$label] Sample $i (${samples[i].length} fitur): '
                '${samples[i].take(6).map((e) => e.toStringAsFixed(3)).join(', ')}...');
          }
          tp.updateData(samples[i]);
        }

        // 4. Render raw data di connected view (tidak perlu timestamp)
        provider.setMockData(samples.last);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue.withOpacity(0.8),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
      child: Text(label),
    );
  }

  Widget _buildScannerView(BLEProvider provider, TranslationProvider tp) {
    if (provider.isScanning) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppTheme.primaryColor),
            const SizedBox(height: 20),
            Text("Mencari Sarung Tangan BISINDO...",
                style: TextStyle(color: Colors.white.withOpacity(0.5))),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => provider.stopScan(),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("Berhenti"),
            )
          ],
        ),
      );
    }

    if (provider.scanResults.isNotEmpty) {
      return Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: provider.scanResults.length,
              itemBuilder: (context, index) {
                final result = provider.scanResults[index];
                String name = result.device.platformName;
                if (name.isEmpty) name = result.advertisementData.advName;
                if (name.isEmpty) name = "Perangkat Tidak Dikenal";

                return ListTile(
                  title: Text(name),
                  subtitle: Text(result.device.remoteId.toString()),
                  textColor: Colors.white,
                  leading: const Icon(Icons.bluetooth, color: AppTheme.primaryColor),
                  trailing: provider.isConnecting 
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                      )
                    : ElevatedButton(
                        onPressed: provider.isConnecting ? null : () => provider.connect(result.device),
                        child: const Text("Hubungkan"),
                      ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10.0),
            child: ElevatedButton.icon(
              onPressed: provider.isConnecting ? null : () => provider.startScan(),
              icon: const Icon(Icons.refresh),
              label: const Text("Pindai Ulang"),
            ),
          ),
        ],
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bluetooth_searching,
              size: 64, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 20),
          Text(
            "Tidak Ada Perangkat Terhubung",
            style: TextStyle(color: Colors.white.withOpacity(0.5)),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => provider.startScan(),
            icon: const Icon(Icons.search),
            label: const Text("Pindai Perangkat"),
          ),
          const SizedBox(height: 20),
          _buildDummyButtonsWidget(tp, provider),
        ],
      ),
    );
  }

  Widget _buildDummyButtonsWidget(TranslationProvider tp, BLEProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 5.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("-- Tes Dummy (Neural Network) --", style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              _buildDebugBtn('A', tp, provider),
              _buildDebugBtn('B', tp, provider),
              _buildDebugBtn('C', tp, provider),
              // _buildDebugBtn('D', tp, provider),
              // _buildDebugBtn('E', tp, provider),
              // _buildDebugBtn('F', tp, provider),
              // _buildDebugBtn('G', tp, provider),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildConnectedView(BLEProvider provider) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
        child: Column(
          children: [
            Pulse(
              infinite: true,
              child: const Icon(Icons.bluetooth_connected,
                  size: 48, color: AppTheme.primaryColor),
            ),
            const SizedBox(height: 8),
            const Text(
              "Terhubung & Streaming",
              style: TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Tampilkan TS (Info saja)
            if (provider.currentData.isNotEmpty)
              Text("TS: ${provider.currentData[0].toInt()}", style: const TextStyle(fontSize: 10, color: Colors.white24)),
            const SizedBox(height: 10),

            // Flex Sensors Section (Indeks: 5, 10, 15, 20, 25)
            _buildDataSection(
              "SENSOR FLEX (mV)",
              provider.currentData.length >= 26 
                ? [
                    provider.currentData[25], // Thumb
                    provider.currentData[20], // Index
                    provider.currentData[15], // Middle
                    provider.currentData[10], // Ring
                    provider.currentData[5],  // Pinky
                  ]
                : [],
              ["Jempol", "Telunjuk", "Tengah", "Manis", "Kelingking"],
            ),
            const SizedBox(height: 15),
            
            // Quaternion Section
            _buildDataSection(
              "QUATERNION (W,X,Y,Z)",
              provider.currentData.length >= 5 
                ? provider.currentData.sublist(1, 5) // Back Q
                : [],
              ["Q_W", "Q_X", "Q_Y", "Q_Z"],
            ),

            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => provider.disconnect(),
              icon: const Icon(Icons.close),
              label: const Text("Putuskan Koneksi"),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.2),
                  foregroundColor: Colors.redAccent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataSection(
      String title, List<double> values, List<String> labels) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 9, color: Colors.white54, letterSpacing: 1.5)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(values.length, (index) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  Text(
                    index < labels.length ? labels[index] : '$index',
                    style: const TextStyle(fontSize: 8, color: Colors.white38),
                  ),
                  Text(
                    values[index].toStringAsFixed(3),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}
