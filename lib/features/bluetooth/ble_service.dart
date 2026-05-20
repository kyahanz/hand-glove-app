import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../translation/dummy_data.dart';

class BLEService {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _dataCharacteristic;
  StreamSubscription? _scanSubscription;

  // Stream for connection state
  final StreamController<BluetoothConnectionState> _connectionStateController =
      StreamController<BluetoothConnectionState>.broadcast();
  Stream<BluetoothConnectionState> get connectionState =>
      _connectionStateController.stream;

  // Stream for incoming data — selalu 33 fitur (TANPA timestamp)
  final StreamController<List<double>> _dataStreamController =
      StreamController<List<double>>.broadcast();
  Stream<List<double>> get dataStream => _dataStreamController.stream;

  bool _isMockMode = false;
  Timer? _mockTimer;
  Timer? _pollTimer;

  bool get isConnected => _connectedDevice?.isConnected ?? false;
  bool get isMockMode => _isMockMode;

  Future<void> init() async {
    if (await FlutterBluePlus.isSupported == false) {
      print("Bluetooth not supported");
      return;
    }
    FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
      print(state);
    });
  }

  Future<void> startScan() async {
    if (_isMockMode) return;
    try {
      await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 200));
      print("Starting BLE Scan (No Filter)...");
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );
    } catch (e) {
      print("Error starting scan: $e");
    }
  }

  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  static final Guid serviceUuid = Guid("0180");
  static final Guid charUuid = Guid("FEF2");

  Future<void> connect(BluetoothDevice device) async {
    int retryCount = 0;
    const int maxRetries = 2;

    while (retryCount <= maxRetries) {
      try {
        print("Connecting to ${device.remoteId} (Attempt ${retryCount + 1})...");

        if (retryCount > 0) {
          await Future.delayed(const Duration(seconds: 1));
        }

        await device.connect(
          timeout: const Duration(seconds: 15),
          autoConnect: false,
          license: License.free,
        );
        _connectedDevice = device;

        device.connectionState.listen((state) {
          _connectionStateController.add(state);
          if (state == BluetoothConnectionState.disconnected) {
            _connectedDevice = null;
            _dataCharacteristic = null;
          }
        });

        try {
          await device.requestMtu(512);
          print("MTU Updated to 512");
        } catch (e) {
          print("Could not update MTU: $e");
        }

        List<BluetoothService> services = await device.discoverServices();
        print("Discovery: Found ${services.length} services");

        for (var service in services) {
          print("Found Service: ${service.uuid.toString().toUpperCase()}");
          if (service.uuid == serviceUuid) {
            print("Target Service Found: $serviceUuid");
            for (var characteristic in service.characteristics) {
              print(
                  "  Found Characteristic: ${characteristic.uuid.toString().toUpperCase()}");
              if (characteristic.uuid == charUuid) {
                print("Target Characteristic (CSV) Found: $charUuid");
                _dataCharacteristic = characteristic;

                if (characteristic.properties.notify) {
                  print("  Properties: Notify supported");
                  await _dataCharacteristic!.setNotifyValue(true);
                  _dataCharacteristic!.lastValueStream.listen((value) {
                    _processData(value);
                  });
                } else {
                  print(
                      "  Properties: Notify NOT supported, relying on manual poll");
                }

                _startPolling();
                return;
              }
            }
          }
        }
        print("WARNING: Target Service/Characteristic NOT found after discovery.");
        return;
      } catch (e) {
        print("Connection attempt ${retryCount + 1} failed: $e");
        retryCount++;
        if (retryCount > maxRetries) rethrow;
      }
    }
  }

  Future<void> disconnect() async {
    _pollTimer?.cancel();
    if (_isMockMode) {
      toggleMockMode(false);
      return;
    }
    await _connectedDevice?.disconnect();
  }

  void _startPolling() {
    _pollTimer?.cancel();

    if (_dataCharacteristic?.properties.notify == true) {
      print("[BLE POLL] Notify aktif — skip manual polling.");
      return;
    }

    print("[BLE POLL] Notify tidak didukung — mulai polling manual (500ms)");
    bool isPolling = false;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (_connectedDevice == null || _dataCharacteristic == null) {
        timer.cancel();
        return;
      }
      if (isPolling) return;
      isPolling = true;
      try {
        List<int> value = await _dataCharacteristic!.read();
        _processData(value);
      } catch (e) {
        print("Error polling data: $e");
      } finally {
        isPolling = false;
      }
    });
  }

  void _processData(List<int> rawData) {
    try {
      String decoded = String.fromCharCodes(rawData).trim();
      if (decoded.isEmpty) {
        print("[BLE FETCH] Received empty payload");
        return;
      }

      print("[BLE FETCH] Raw Data: $decoded");

      List<double> sensorValues = decoded
          .split(',')
          .map((e) => double.tryParse(e.trim()) ?? 0.0)
          .toList();

      print("Data Received: Found ${sensorValues.length} values");

      // Format CSV dari ESP32: timestamp,hand_w,hand_x,...,index_dip (34 nilai)
      // ✅ Strip timestamp (index 0), kirim hanya 33 fitur ke pipeline
      if (sensorValues.length >= 34) {
        final features = sensorValues.sublist(1, 34);
        _dataStreamController.add(features);
      } else {
        print(
            "WARNING: Data format invalid. Expected >= 34 (1 TS + 33 fitur), got ${sensorValues.length}");
        print("Raw Data: $decoded");
      }
    } catch (e) {
      print("Error parsing data: $e");
    }
  }

  // ─── MOCK MODE ──────────────────────────────────────────────────────────────

  void toggleMockMode(bool enabled) {
    _isMockMode = enabled;
    if (_isMockMode) {
      _startMockDataStream();
      _connectionStateController.add(BluetoothConnectionState.connected);
    } else {
      _mockTimer?.cancel();
      _connectionStateController.add(BluetoothConnectionState.disconnected);
    }
  }

  int _mockIndex = 0;
  int _mockLabelIndex = 0;
  final List<String> _mockLabels = ['A', 'B', 'C', 'D', 'E', 'F', 'G'];

  void _startMockDataStream() {
    _mockTimer?.cancel();
    _mockIndex = 0;
    _mockLabelIndex = 0;

    _mockTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      final String currentLabel = _mockLabels[_mockLabelIndex];
      final samples = DummyData.samples[currentLabel]!;

      // ✅ FIX: Kirim 33 fitur TANPA timestamp
      // BLEService._processData sudah strip timestamp dari data BLE asli,
      // mock mode harus konsisten — langsung kirim 33 fitur saja.
      final List<double> features = List<double>.from(samples[_mockIndex]);
      _dataStreamController.add(features);

      _mockIndex++;

      // Ganti huruf setiap 10 sample (300ms × 10 = 3 detik per huruf)
      // Debounce butuh 5 frame stabil → 300ms × 5 = 1.5 detik sebelum huruf muncul
      if (_mockIndex >= samples.length) {
        _mockIndex = 0;
        _mockLabelIndex = (_mockLabelIndex + 1) % _mockLabels.length;
        print("[MOCK] Ganti huruf → ${_mockLabels[_mockLabelIndex]}");
      }
    });
  }

  void dispose() {
    _scanSubscription?.cancel();
    _connectionStateController.close();
    _dataStreamController.close();
    _mockTimer?.cancel();
    _pollTimer?.cancel();
  }
}