import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/device_model.dart';

class BluetoothDiscoveryService {
  StreamSubscription<List<ScanResult>>? _scanSub;
  final Map<String, BluetoothDeviceItem> _foundMap = {};
  final StreamController<List<BluetoothDeviceItem>> _devicesController =
      StreamController<List<BluetoothDeviceItem>>.broadcast();

  Stream<List<BluetoothDeviceItem>> get devicesStream => _devicesController.stream;

  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final scanOk = statuses[Permission.bluetoothScan]?.isGranted ?? true;
    final locOk = statuses[Permission.locationWhenInUse]?.isGranted ?? true;
    return scanOk || locOk;
  }

  Future<void> startScan() async {
    _foundMap.clear();
    _devicesController.add([]);

    final hasPerm = await requestPermissions();
    if (!hasPerm) return;

    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final pName = r.device.platformName.trim();
        final aName = r.advertisementData.advName.trim();
        final resolvedName = pName.isNotEmpty ? pName : aName;

        if (resolvedName.isEmpty || r.rssi < -88) {
          continue;
        }

        _foundMap[r.device.remoteId.str] = BluetoothDeviceItem(
          id: r.device.remoteId.str,
          name: resolvedName,
          rssi: r.rssi,
        );
      }
      final list = _foundMap.values.toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi));
      _devicesController.add(list);
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    } catch (_) {}
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSub?.cancel();
  }

  void dispose() {
    stopScan();
    _devicesController.close();
  }
}
