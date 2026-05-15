
import 'dart:async';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../translation/dummy_data.dart';

class BLEService {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _dataCharacteristic;
  StreamSubscription? _scanSubscription;
  
  // Stream for connection state
  final StreamController<BluetoothConnectionState> _connectionStateController = 
      StreamController<BluetoothConnectionState>.broadcast();
  Stream<BluetoothConnectionState> get connectionState => _connectionStateController.stream;

  // Stream for incoming data (List of integers/floats from sensor)
  final StreamController<List<double>> _dataStreamController = 
      StreamController<List<double>>.broadcast();
  Stream<List<double>> get dataStream => _dataStreamController.stream;

  bool _isMockMode = false;
  Timer? _mockTimer;
  Timer? _pollTimer;

  bool get isConnected => _connectedDevice?.isConnected ?? false;
  bool get isMockMode => _isMockMode;

  Future<void> init() async {
    // Check adapter state
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
        // Safety: stop previous scan if any
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

        await device.connect(timeout: const Duration(seconds: 15), autoConnect: false, license: License.free);
        _connectedDevice = device;

        // Listener status koneksi (selalu register)
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
              print("  Found Characteristic: ${characteristic.uuid.toString().toUpperCase()}");
              if (characteristic.uuid == charUuid) {
                print("Target Characteristic (CSV) Found: $charUuid");
                _dataCharacteristic = characteristic;
                
                // Aktifkan notify jika didukung
                if (characteristic.properties.notify) {
                  print("  Properties: Notify supported");
                  await _dataCharacteristic!.setNotifyValue(true);
                  _dataCharacteristic!.lastValueStream.listen((value) {
                    _processData(value);
                  });
                } else {
                  print("  Properties: Notify NOT supported, relying on manual poll");
                }

                // Mulai Polling Manual per 2 detik (Sesuai Permintaan User)
                _startPolling();
                
                return; // Success
              }
            }
          }
        }
        print("WARNING: Target Service/Characteristic NOT found after discovery.");
        return; // Berhasil konek
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
    
    // Jika notify sudah aktif, tidak perlu polling manual.
    // Android GATT tidak bisa handle concurrent read + notify.
    if (_dataCharacteristic?.properties.notify == true) {
      print("[BLE POLL] Notify aktif — skip manual polling.");
      return;
    }

    print("[BLE POLL] Notify tidak didukung — mulai polling manual (500ms)");
    bool _isPolling = false; // Guard untuk mencegah concurrent read
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (_connectedDevice == null || _dataCharacteristic == null) {
        timer.cancel();
        return;
      }
      // Skip jika read sebelumnya belum selesai
      if (_isPolling) return;
      _isPolling = true;
      try {
        List<int> value = await _dataCharacteristic!.read();
        _processData(value);
      } catch (e) {
        print("Error polling data: $e");
      } finally {
        _isPolling = false;
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

      // Parse semua nilai CSV
      List<double> sensorValues = decoded.split(',')
          .map((e) => double.tryParse(e.trim()) ?? 0.0)
          .toList();

      print("Data Received: Found ${sensorValues.length} values");

      // Protokol baru: 34 nilai (1 timestamp + 33 fitur)
      // Format CSV dari ESP32: timestamp,hand_w,hand_x,...,index_dip
      if (sensorValues.length >= 34) {
        // ✅ Strip timestamp (index 0), kirim hanya 33 fitur ke pipeline
        final features = sensorValues.sublist(1, 34);
        _dataStreamController.add(features);
      } else {
        print("WARNING: Data format invalid. Expected >= 34 (1 TS + 33 fitur), got ${sensorValues.length}");
        print("Raw Data: $decoded");
      }
    } catch (e) {
      print("Error parsing data: $e");
    }
  }

  // --- MOCK MODE ---
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
    _mockTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      // Loop bergiliran A -> B -> C -> D -> E -> F -> G
      String currentLabel = _mockLabels[_mockLabelIndex];
      final samples = DummyData.samples[currentLabel]!;
      
      List<double> mockData = [];
      mockData.add(DateTime.now().millisecondsSinceEpoch.toDouble()); // TS
      mockData.addAll(samples[_mockIndex]);
      
      _mockIndex++;
      
      // Ganti huruf setiap 10 sampel (karena 500ms * 10 = 5 detik per huruf)
      if (_mockIndex >= 10) {
        _mockIndex = 0;
        _mockLabelIndex = (_mockLabelIndex + 1) % _mockLabels.length;
      }
      
      _dataStreamController.add(mockData);
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
