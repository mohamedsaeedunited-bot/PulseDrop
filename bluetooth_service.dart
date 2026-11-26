import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/device_model.dart';

enum BtUiStatus {
  idle,
  unsupported,
  permissionDenied,
  permissionPermanentlyDenied,
  bluetoothOff,
  scanning,
  ready,
  error,
}

class BluetoothDiscoveryService {
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanningSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  final Map<String, BluetoothDeviceItem> _foundMap = {};

  final ValueNotifier<List<BluetoothDeviceItem>> devicesNotifier =
      ValueNotifier<List<BluetoothDeviceItem>>([]);
  final ValueNotifier<BtUiStatus> statusNotifier =
      ValueNotifier<BtUiStatus>(BtUiStatus.idle);
  final ValueNotifier<bool> isScanningNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String?> errorMessageNotifier =
      ValueNotifier<String?>(null);

  bool _initializedListeners = false;

  void _ensureListeners() {
    if (_initializedListeners) return;
    _initializedListeners = true;

    _isScanningSub = FlutterBluePlus.isScanning.listen((scanning) {
      isScanningNotifier.value = scanning;
      if (!scanning && statusNotifier.value == BtUiStatus.scanning) {
        statusNotifier.value = BtUiStatus.ready;
      }
    });

    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.off) {
        statusNotifier.value = BtUiStatus.bluetoothOff;
        isScanningNotifier.value = false;
      } else if (state == BluetoothAdapterState.on &&
          statusNotifier.value == BtUiStatus.bluetoothOff) {
        startScan();
      }
    });
  }

  Future<bool> _ensurePermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final scanStatus = statuses[Permission.bluetoothScan];
    final connectStatus = statuses[Permission.bluetoothConnect];
    final locStatus = statuses[Permission.locationWhenInUse];

    final permanentlyDenied =
        (scanStatus?.isPermanentlyDenied ?? false) ||
        (connectStatus?.isPermanentlyDenied ?? false);

    if (permanentlyDenied) {
      statusNotifier.value = BtUiStatus.permissionPermanentlyDenied;
      return false;
    }

    // Android 12+ requires bluetoothScan & bluetoothConnect; older Android relies on location
    final modernGranted = (scanStatus?.isGranted ?? false) &&
        (connectStatus?.isGranted ?? false);
    final legacyGranted = locStatus?.isGranted ?? false;

    if (!modernGranted && !legacyGranted) {
      statusNotifier.value = BtUiStatus.permissionDenied;
      return false;
    }

    return true;
  }

  bool _isValidReadableName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length < 2) return false;
    // Filter out raw MAC addresses or hex-only unnamed identifiers
    final macPattern = RegExp(r'^([0-9A-Fa-f]{2}[:\-]){5}[0-9A-Fa-f]{2}$');
    if (macPattern.hasMatch(trimmed)) return false;
    return true;
  }

  void _publishDevices() {
    final list = _foundMap.values.toList()
      ..sort((a, b) {
        // Paired devices with live signal first, then nearby by RSSI, then paired offline
        if (a.isPaired != b.isPaired) {
          return a.isPaired ? -1 : 1;
        }
        return b.rssi.compareTo(a.rssi);
      });
    devicesNotifier.value = list;
  }

  Future<void> _loadBondedDevices() async {
    if (!Platform.isAndroid) return;
    try {
      final bonded = await FlutterBluePlus.bondedDevices;
      for (final d in bonded) {
        final name = d.platformName.trim();
        if (_isValidReadableName(name)) {
          _foundMap[d.remoteId.str] = BluetoothDeviceItem(
            id: d.remoteId.str,
            name: name,
            rssi: 0,
            isPaired: true,
          );
        }
      }
      _publishDevices();
    } catch (_) {}
  }

  Future<void> turnOnBluetooth() async {
    try {
      if (Platform.isAndroid) {
        await FlutterBluePlus.turnOn();
        await Future.delayed(const Duration(milliseconds: 600));
        await startScan();
      }
    } catch (e) {
      errorMessageNotifier.value = 'تعذر تشغيل البلوتوث تلقائياً، فعّله من شريط الإشعارات.';
    }
  }

  Future<void> startScan() async {
    _ensureListeners();
    errorMessageNotifier.value = null;

    try {
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) {
        statusNotifier.value = BtUiStatus.unsupported;
        return;
      }
    } catch (_) {}

    final hasPerm = await _ensurePermissions();
    if (!hasPerm) return;

    try {
      final state = await FlutterBluePlus.adapterState.first
          .timeout(const Duration(seconds: 3));
      if (state != BluetoothAdapterState.on) {
        statusNotifier.value = BtUiStatus.bluetoothOff;
        return;
      }
    } catch (_) {}

    _foundMap.clear();
    devicesNotifier.value = [];
    statusNotifier.value = BtUiStatus.scanning;

    // 1. Immediately display paired phones & trusted devices by real name
    await _loadBondedDevices();

    // 2. Live BLE scan for nearby named devices
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      bool changed = false;
      for (final r in results) {
        final pName = r.device.platformName.trim();
        final aName = r.advertisementData.advName.trim();
        final resolvedName = pName.isNotEmpty ? pName : aName;

        if (!_isValidReadableName(resolvedName) || r.rssi < -85) {
          continue;
        }

        final id = r.device.remoteId.str;
        final wasPaired = _foundMap[id]?.isPaired ?? false;
        _foundMap[id] = BluetoothDeviceItem(
          id: id,
          name: resolvedName,
          rssi: r.rssi,
          isPaired: wasPaired,
        );
        changed = true;
      }
      if (changed) {
        _publishDevices();
      }
    });

    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 12),
      );
    } catch (e) {
      errorMessageNotifier.value = e.toString();
      statusNotifier.value = _foundMap.isNotEmpty ? BtUiStatus.ready : BtUiStatus.error;
    }
  }

  Future<void> stopScan() async {
    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
    } catch (_) {}
    await _scanSub?.cancel();
    _scanSub = null;
  }

  void dispose() {
    stopScan();
    _isScanningSub?.cancel();
    _adapterSub?.cancel();
    devicesNotifier.dispose();
    statusNotifier.dispose();
    isScanningNotifier.dispose();
    errorMessageNotifier.dispose();
  }
}
