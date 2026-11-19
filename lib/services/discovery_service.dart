import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/models.dart';

class DiscoveryService extends ChangeNotifier {
  static const int udpPort = 53318;
  static const int httpPort = 53317;

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;

  final String deviceId;
  String deviceName;
  String? localIp;
  bool stealthMode = false;

  final Map<String, PeerDevice> _peers = {};
  List<PeerDevice> get peers => _peers.values.toList();

  DiscoveryService({required this.deviceId, required this.deviceName});

  Future<void> start() async {
    await refreshLocalIp();
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        udpPort,
        reuseAddress: true,
        reusePort: false,
      );
      _socket?.broadcastEnabled = true;

      _socket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket?.receive();
          if (datagram == null) return;
          _handleDatagram(datagram);
        }
      });

      _broadcastTimer?.cancel();
      _broadcastTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!stealthMode) _sendAnnouncement();
      });
      if (!stealthMode) _sendAnnouncement();

      _cleanupTimer?.cancel();
      _cleanupTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        final now = DateTime.now();
        final before = _peers.length;
        _peers.removeWhere((_, peer) => now.difference(peer.lastSeen).inSeconds > 8);
        if (_peers.length != before) {
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint('Discovery error: $e');
    }
  }

  void toggleStealth() {
    stealthMode = !stealthMode;
    if (!stealthMode) _sendAnnouncement();
    notifyListeners();
  }

  Future<String?> refreshLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      String? fallbackIp;
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.')) {
            if (name.contains('wlan') || name.contains('ap') || name.contains('swlan')) {
              localIp = ip;
              notifyListeners();
              return localIp;
            }
            fallbackIp ??= ip;
          }
        }
      }
      localIp = fallbackIp;
      notifyListeners();
      return localIp;
    } catch (e) {
      debugPrint('IP lookup error: $e');
      return null;
    }
  }

  void updateDeviceName(String newName) {
    deviceName = newName;
    if (!stealthMode) _sendAnnouncement();
    notifyListeners();
  }

  void _sendAnnouncement() {
    if (_socket == null) return;
    final payload = jsonEncode({
      'app': 'PulseDrop',
      'id': deviceId,
      'name': deviceName,
      'port': httpPort,
    });
    final bytes = utf8.encode(payload);
    try {
      _socket?.send(bytes, InternetAddress('255.255.255.255'), udpPort);
      if (localIp != null) {
        final parts = localIp!.split('.');
        if (parts.length == 4) {
          final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
          _socket?.send(bytes, InternetAddress(subnetBroadcast), udpPort);
        }
      }
    } catch (_) {}
  }

  void _handleDatagram(Datagram datagram) {
    try {
      final msg = utf8.decode(datagram.data);
      final data = jsonDecode(msg) as Map<String, dynamic>;
      if (data['app'] != 'PulseDrop') return;
      final peerId = data['id']?.toString() ?? '';
      if (peerId.isEmpty || peerId == deviceId) return;

      final ip = datagram.address.address;
      if (ip == localIp) return;

      _peers[peerId] = PeerDevice(
        id: peerId,
        name: data['name']?.toString() ?? 'PulseDrop Device',
        ip: ip,
        port: (data['port'] is int) ? data['port'] : httpPort,
        lastSeen: DateTime.now(),
      );
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _broadcastTimer?.cancel();
    _cleanupTimer?.cancel();
    _socket?.close();
    super.dispose();
  }
}
