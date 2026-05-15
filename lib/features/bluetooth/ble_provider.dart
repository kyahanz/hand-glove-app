
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_service.dart';

class BLEProvider with ChangeNotifier {
  final BLEService _service = BLEService();
  
  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;
  List<double> _currentData = [];
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _isConnecting = false;

  BLEProvider() {
    _init();
  }

  void _init() async {
    await _service.init();
    
    // Listen to isScanning state directly from FlutterBluePlus
    FlutterBluePlus.isScanning.listen((scanning) {
      _isScanning = scanning;
      notifyListeners();
    });

    _service.connectionState.listen((state) {
      _connectionState = state;
      notifyListeners();
    });
    _service.dataStream.listen((data) {
      _currentData = data;
      notifyListeners(); // Now we notify to make UI responsive
    });
    // Listen to scan results
    _service.scanResults.listen((results) {
        _scanResults = results;
        notifyListeners();
    });
  }

  BluetoothConnectionState get connectionState => _connectionState;
  List<double> get currentData => _currentData;
  List<ScanResult> get scanResults => _scanResults;
  bool get isScanning => _isScanning;
  bool get isConnecting => _isConnecting;
  bool get isMockMode => _service.isMockMode;
  Stream<List<double>> get dataStream => _service.dataStream;

  void toggleMockMode(bool enabled) {
    _service.toggleMockMode(enabled);
    notifyListeners();
  }

  void setMockData(List<double> data) {
    _currentData = data;
    notifyListeners();
  }

  Future<void> startScan() async {
    _isScanning = true;
    _scanResults.clear(); // Hapus daftar lama agar UI ter-refresh
    notifyListeners();
    try {
      await _service.startScan();
    } catch (e) {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    await _service.stopScan();
  }

  Future<void> connect(BluetoothDevice device) async {
    _isConnecting = true;
    notifyListeners();
    try {
      await _service.connect(device);
      stopScan();
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _service.disconnect();
  }
}
