import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_model.dart';

class NetworkService {
  static const int serverPort = 8080;
  static const int udpDiscoveryPort = 8081;

  int activePort = serverPort;
  HttpServer? _server;
  RawDatagramSocket? _udpSocket;
  Timer? _beaconTimer;

  String deviceName = 'PulseDrop Phone';
  String? localIp;
  List<String> _allLocalIps = [];
  bool isVisible = true;

  final List<File> sharedWebFiles = [];

  final ValueNotifier<String?> localIpNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<List<NetworkDevice>> discoveredDevices =
      ValueNotifier<List<NetworkDevice>>([]);
  final ValueNotifier<bool> isScanning = ValueNotifier<bool>(false);
  final ValueNotifier<TransferProgress?> activeTransfer =
      ValueNotifier<TransferProgress?>(null);

  final StreamController<TransferRecord> _transferController =
      StreamController<TransferRecord>.broadcast();
  final StreamController<ChatMessage> _chatController =
      StreamController<ChatMessage>.broadcast();

  Stream<TransferRecord> get onTransfer => _transferController.stream;
  Stream<ChatMessage> get onChat => _chatController.stream;

  Future<void> loadDeviceName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('pulsedrop_device_name');
      if (saved != null && saved.trim().isNotEmpty) {
        deviceName = saved.trim();
      } else {
        deviceName = 'PulseDrop (${Platform.localHostname})';
      }
    } catch (_) {}
  }

  Future<void> saveDeviceName(String newName) async {
    if (newName.trim().isEmpty) return;
    deviceName = newName.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pulsedrop_device_name', deviceName);
    } catch (_) {}
    sendUdpBeacon();
  }

  Future<String?> getLocalIpAddress() async {
    final foundIps = <String>[];
    String? preferredIp;

    try {
      final info = NetworkInfo();
      final wifiIp = await info.getWifiIP();
      if (wifiIp != null && wifiIp.isNotEmpty && wifiIp != '0.0.0.0') {
        foundIps.add(wifiIp);
        if (wifiIp.startsWith('192.168.')) {
          preferredIp = wifiIp;
        }
      }
    } catch (_) {}

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final iface in interfaces) {
        final ifName = iface.name.toLowerCase();
        // Skip cellular mobile data, VPN, and dummy interfaces
        if (ifName.contains('rmnet') ||
            ifName.contains('ccmni') ||
            ifName.contains('pdp') ||
            ifName.contains('tun') ||
            ifName.contains('ppp') ||
            ifName.contains('dummy')) {
          continue;
        }
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final ip = addr.address;
          if (!foundIps.contains(ip)) {
            foundIps.add(ip);
          }
          if (preferredIp == null &&
              (ifName.contains('wlan') ||
                  ifName.contains('swlan') ||
                  ifName.contains('ap') ||
                  ip.startsWith('192.168.'))) {
            preferredIp = ip;
          }
        }
      }
    } catch (_) {}

    _allLocalIps = foundIps;
    localIp = preferredIp ?? (foundIps.isNotEmpty ? foundIps.first : localIp);
    localIpNotifier.value = localIp;
    return localIp;
  }

  String? _findMatchingLocalIp(String targetIp) {
    final parts = targetIp.split('.');
    if (parts.length != 4) return localIp;
    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}.';
    for (final ip in _allLocalIps) {
      if (ip.startsWith(prefix)) {
        return ip;
      }
    }
    return null;
  }

  /// Creates an HttpClient bound to the matching Wi-Fi/Hotspot interface so Android
  /// NEVER misroutes local transfers over 4G/5G Mobile Data.
  HttpClient _createBoundClient(
    String targetIp, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    final client = HttpClient()..connectionTimeout = timeout;
    final matchedLocal = _findMatchingLocalIp(targetIp);
    if (matchedLocal != null) {
      client.connectionFactory =
          (Uri uri, String? proxyHost, int? proxyPort) async {
        try {
          return await Socket.startConnect(
            uri.host,
            uri.port,
            sourceAddress: InternetAddress(matchedLocal),
          );
        } catch (_) {
          return await Socket.startConnect(uri.host, uri.port);
        }
      };
    }
    return client;
  }

  Future<void> startServices() async {
    await loadDeviceName();
    await getLocalIpAddress();
    await _startHttpServer();
    await _startUdpDiscovery();
    startAutoDiscovery();
  }

  Future<void> ensureServicesAlive() async {
    await getLocalIpAddress();
    if (_server == null) {
      await _startHttpServer();
    }
    if (_udpSocket == null) {
      await _startUdpDiscovery();
    }
    sendUdpBeacon();
  }

  Future<void> stopServices() async {
    _beaconTimer?.cancel();
    _udpSocket?.close();
    _udpSocket = null;
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _startHttpServer() async {
    if (_server != null) return;
    const portsToTry = [8080, 8088, 8090, 9090, 0];
    for (final port in portsToTry) {
      try {
        _server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          port,
          shared: true,
        );
        activePort = _server!.port;
        _server!.listen(_handleRequest);
        return;
      } catch (_) {}
    }
  }

  Future<void> _startUdpDiscovery() async {
    if (_udpSocket != null) return;
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        udpDiscoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = _udpSocket!.receive();
          if (dg == null) return;
          try {
            final msg = utf8.decode(dg.data);
            final data = jsonDecode(msg);
            if (data['app'] == 'PulseDrop') {
              final senderIp = dg.address.address;
              if (!_allLocalIps.contains(senderIp) &&
                  senderIp != localIp &&
                  senderIp != '127.0.0.1') {
                _registerDiscoveredDevice(
                  NetworkDevice(
                    name: data['name'] ?? 'PulseDrop Device',
                    ip: senderIp,
                    port: data['port'] ?? serverPort,
                    version: data['version'] ?? '5.2',
                  ),
                );
                if (data['type'] == 'DISCOVER' && isVisible) {
                  _sendUdpPacket(dg.address, 'REPLY');
                }
              }
            }
          } catch (_) {}
        }
      });

      _beaconTimer?.cancel();
      _beaconTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (isVisible) sendUdpBeacon();
      });
    } catch (_) {}
  }

  void _sendUdpPacket(InternetAddress target, String type) {
    if (_udpSocket == null || !isVisible) return;
    try {
      final payload = utf8.encode(jsonEncode({
        'app': 'PulseDrop',
        'type': type,
        'name': deviceName,
        'port': activePort,
        'version': '5.2',
      }));
      _udpSocket!.send(payload, target, udpDiscoveryPort);
    } catch (_) {}
  }

  void sendUdpBeacon() {
    _sendUdpPacket(InternetAddress('255.255.255.255'), 'DISCOVER');
    final allSubnets = <String>{};
    for (final ip in _allLocalIps) {
      final parts = ip.split('.');
      if (parts.length == 4) {
        allSubnets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
      }
    }
    for (final bcast in allSubnets) {
      try {
        _sendUdpPacket(InternetAddress(bcast), 'DISCOVER');
      } catch (_) {}
    }
  }

  void _registerDiscoveredDevice(NetworkDevice device) {
    final current = List<NetworkDevice>.from(discoveredDevices.value);
    final idx = current.indexWhere((d) => d.ip == device.ip);
    if (idx >= 0) {
      current[idx] = device;
    } else {
      current.add(device);
    }
    discoveredDevices.value = current;
  }

  /// Dual Auto-Discovery across ALL local Wi-Fi and Hotspot interfaces
  Future<void> startAutoDiscovery() async {
    await ensureServicesAlive();

    if (isScanning.value) return;
    isScanning.value = true;

    try {
      final candidates = <String>{
        '192.168.43.1',
        '192.168.137.1',
        '172.20.10.1',
        '192.168.1.1',
        '192.168.0.1',
      };

      for (final ip in _allLocalIps) {
        final parts = ip.split('.');
        if (parts.length == 4) {
          final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
          for (int i = 1; i <= 254; i++) {
            candidates.add('$subnet.$i');
          }
        }
      }

      for (final ip in _allLocalIps) {
        candidates.remove(ip);
      }

      final list = candidates.toList();
      const batchSize = 40;
      for (int start = 0; start < list.length; start += batchSize) {
        final batch = list.skip(start).take(batchSize);
        await Future.wait(batch.map((ip) => _probeDeviceHttp(ip)));
      }
    } finally {
      isScanning.value = false;
    }
  }

  Future<void> _probeDeviceHttp(String targetIp) async {
    for (final port in [serverPort, 8088]) {
      final client = _createBoundClient(
        targetIp,
        timeout: const Duration(milliseconds: 450),
      );
      try {
        final request = await client
            .getUrl(Uri.parse('http://$targetIp:$port/ping'))
            .timeout(const Duration(milliseconds: 500));
        final response =
            await request.close().timeout(const Duration(milliseconds: 500));
        if (response.statusCode == 200) {
          final body = await utf8.decoder.bind(response).join();
          final data = jsonDecode(body);
          if (data['app'] == 'PulseDrop') {
            _registerDiscoveredDevice(
              NetworkDevice(
                name: data['name'] ?? 'PulseDrop Device',
                ip: targetIp,
                port: data['port'] ?? port,
                version: data['version'] ?? '5.2',
              ),
            );
            return;
          }
        }
      } catch (_) {
      } finally {
        client.close(force: true);
      }
    }
  }

  String _safeDecode(String raw) {
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    final path = request.uri.path;

    if (path == '/ping' && request.method == 'GET') {
      if (!isVisible) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'app': 'PulseDrop',
        'name': deviceName,
        'port': activePort,
        'version': '5.2',
      }));
      await request.response.close();
      return;
    }

    if (path == '/chat' && request.method == 'POST') {
      final body = await utf8.decoder.bind(request).join();
      try {
        final data = jsonDecode(body);
        _chatController.add(ChatMessage(
          sender: data['sender'] ?? 'جهاز قريب',
          text: data['text'] ?? '',
          timestamp: DateTime.now(),
          isMe: false,
        ));
      } catch (_) {}
      request.response.statusCode = HttpStatus.ok;
      request.response.write('OK');
      await request.response.close();
      return;
    }

    if (path == '/upload' && request.method == 'POST') {
      final rawName = request.headers.value('x-file-name') ??
          'file_${DateTime.now().millisecondsSinceEpoch}';
      final decodedName = _safeDecode(rawName);
      final cleanName = decodedName.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
      final senderName = _safeDecode(
        request.headers.value('x-sender-name') ?? 'جهاز قريب',
      );
      final declaredSize = int.tryParse(
            request.headers.value('x-file-size') ??
                request.headers.value('content-length') ??
                '0',
          ) ??
          0;

      int receivedBytes = 0;
      RandomAccessFile? raf;

      try {
        final dir = await _getWritableDownloadDirectory();
        final saveFile = _buildUniqueFile(dir, cleanName);
        raf = await saveFile.open(mode: FileMode.write);

        final stopwatch = Stopwatch()..start();
        int lastUiUpdateMs = 0;

        activeTransfer.value = TransferProgress(
          fileName: cleanName,
          filePath: saveFile.path,
          peerName: senderName,
          isSending: false,
          bytesTransferred: 0,
          totalBytes: declaredSize,
          speedBytesPerSec: 0,
          remainingSeconds: 0,
        );

        await for (final chunk in request) {
          await raf.writeFrom(chunk);
          receivedBytes += chunk.length;

          final elapsedMs = stopwatch.elapsedMilliseconds;
          if (elapsedMs - lastUiUpdateMs >= 120) {
            lastUiUpdateMs = elapsedMs;
            final speed =
                elapsedMs > 0 ? (receivedBytes / (elapsedMs / 1000.0)) : 0.0;
            final remaining = (declaredSize > receivedBytes && speed > 0)
                ? ((declaredSize - receivedBytes) / speed).ceil()
                : 0;
            activeTransfer.value = TransferProgress(
              fileName: cleanName,
              filePath: saveFile.path,
              peerName: senderName,
              isSending: false,
              bytesTransferred: receivedBytes,
              totalBytes: declaredSize > 0 ? declaredSize : receivedBytes,
              speedBytesPerSec: speed,
              remainingSeconds: remaining,
            );
          }
        }
        await raf.flush();
        await raf.close();
        raf = null;

        final totalFinal = declaredSize > 0 ? declaredSize : receivedBytes;
        activeTransfer.value = TransferProgress(
          fileName: cleanName,
          filePath: saveFile.path,
          peerName: senderName,
          isSending: false,
          bytesTransferred: totalFinal,
          totalBytes: totalFinal,
          speedBytesPerSec: 0,
          remainingSeconds: 0,
          isCompleted: true,
        );

        _transferController.add(TransferRecord(
          fileName: cleanName,
          filePath: saveFile.path,
          peerName: senderName,
          isSent: false,
          timestamp: DateTime.now(),
          sizeBytes: receivedBytes,
        ));

        request.response.statusCode = HttpStatus.ok;
        request.response.write('UPLOADED');
        await request.response.close();
      } catch (e) {
        try {
          await raf?.close();
        } catch (_) {}
        activeTransfer.value = TransferProgress(
          fileName: cleanName,
          peerName: senderName,
          isSending: false,
          bytesTransferred: receivedBytes,
          totalBytes: declaredSize,
          speedBytesPerSec: 0,
          remainingSeconds: 0,
          isFailed: true,
          errorMessage: 'خطأ في حفظ الملف على الجهاز المستلم: $e',
        );
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('SAVE_ERROR: $e');
        await request.response.close();
      }
      return;
    }

    if (path.startsWith('/download/') && request.method == 'GET') {
      final idxStr = path.replaceFirst('/download/', '');
      final idx = int.tryParse(idxStr);
      if (idx != null && idx >= 0 && idx < sharedWebFiles.length) {
        final file = sharedWebFiles[idx];
        if (await file.exists()) {
          final name = file.path.split('/').last;
          request.response.headers.set(
            'Content-Disposition',
            'attachment; filename="${Uri.encodeComponent(name)}"',
          );
          await request.response.addStream(file.openRead());
          await request.response.close();
          return;
        }
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    request.response.headers.contentType = ContentType.html;
    request.response.write(_buildWebPortalHtml());
    await request.response.close();
  }

  /// Avoids Scoped Storage collisions with files owned by previous installs
  File _buildUniqueFile(Directory dir, String fileName) {
    File candidate = File('${dir.path}/$fileName');
    if (!candidate.existsSync()) return candidate;

    final dotIdx = fileName.lastIndexOf('.');
    final base = dotIdx > 0 ? fileName.substring(0, dotIdx) : fileName;
    final ext = dotIdx > 0 ? fileName.substring(dotIdx) : '';
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return File('${dir.path}/${base}_$stamp$ext');
  }

  /// Tests ACTUAL write access before choosing a folder (fixes Android 11-16 Scoped Storage errors)
  Future<Directory> _getWritableDownloadDirectory() async {
    final candidates = <Directory>[
      Directory('/storage/emulated/0/Download/PulseDrop'),
      Directory('/storage/emulated/0/Download/PulseDrop_Received'),
    ];

    try {
      final extAppDir = await getExternalStorageDirectory();
      if (extAppDir != null) {
        candidates.add(Directory('${extAppDir.path}/PulseDrop'));
      }
    } catch (_) {}

    try {
      final docDir = await getApplicationDocumentsDirectory();
      candidates.add(Directory('${docDir.path}/PulseDrop'));
    } catch (_) {}

    for (final dir in candidates) {
      try {
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final probe = File(
          '${dir.path}/.pd_write_test_${DateTime.now().microsecondsSinceEpoch}',
        );
        await probe.writeAsString('ok', flush: true);
        if (await probe.exists()) {
          await probe.delete();
        }
        return dir;
      } catch (_) {
        continue;
      }
    }
    return await getApplicationDocumentsDirectory();
  }

  String _buildWebPortalHtml() {
    final buffer = StringBuffer();
    for (int i = 0; i < sharedWebFiles.length; i++) {
      final name = sharedWebFiles[i].path.split('/').last;
      buffer.writeln(
        '<div class="file-item"><span>$name</span><a href="/download/$i" class="btn">تحميل</a></div>',
      );
    }
    final filesHtml = sharedWebFiles.isEmpty
        ? '<p style="color:#64748b">لم يتم اختيار ملفات للمشاركة بعد من التطبيق.</p>'
        : buffer.toString();

    return '''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>PulseDrop Web Portal</title>
<style>
  body { font-family: system-ui, sans-serif; background: #f8fafc; color: #0f172a; margin: 0; padding: 20px; }
  .card { max-width: 520px; margin: 0 auto; background: #fff; border-radius: 16px; padding: 24px; box-shadow: 0 4px 20px rgba(0,0,0,0.08); }
  h1 { color: #0284c7; margin-top: 0; font-size: 22px; }
  .file-item { display: flex; justify-content: space-between; align-items: center; padding: 12px; border: 1px solid #e2e8f0; border-radius: 10px; margin-bottom: 10px; }
  .btn { background: #0284c7; color: #fff; text-decoration: none; padding: 8px 16px; border-radius: 8px; border: none; cursor: pointer; font-size: 14px; }
  .upload-box { margin-top: 20px; padding-top: 16px; border-top: 1px solid #e2e8f0; }
</style>
</head>
<body>
  <div class="card">
    <h1>⚡ PulseDrop — بوابة الويب</h1>
    <p>الجهاز: <strong>$deviceName</strong></p>
    <h3>الملفات المتاحة للتحميل</h3>
    $filesHtml
    <div class="upload-box">
      <h3>إرسال ملف إلى الموبايل</h3>
      <input type="file" id="fileInput" />
      <button class="btn" onclick="uploadFile()">إرسال</button>
      <p id="status"></p>
    </div>
  </div>
  <script>
    async function uploadFile() {
      const input = document.getElementById('fileInput');
      if (!input.files.length) return;
      const file = input.files[0];
      document.getElementById('status').innerText = 'جاري الإرسال...';
      const res = await fetch('/upload', {
        method: 'POST',
        headers: {
          'x-file-name': encodeURIComponent(file.name),
          'x-file-size': file.size.toString(),
          'x-sender-name': encodeURIComponent('متصفح الويب')
        },
        body: file
      });
      document.getElementById('status').innerText = res.ok ? '✅ تم الإرسال بنجاح!' : '❌ فشل الإرسال';
    }
  </script>
</body>
</html>
''';
  }

  /// Streamed File Upload bound to the matching Wi-Fi/Hotspot interface with real progress & diagnostics
  Future<bool> sendFileToDevice(NetworkDevice device, File file) async {
    await getLocalIpAddress();
    final fileName = file.path.split('/').last;
    final totalBytes = await file.length();
    final client = _createBoundClient(
      device.ip,
      timeout: const Duration(seconds: 12),
    );

    int sentBytes = 0;
    String errorReason = '';
    final stopwatch = Stopwatch()..start();
    int lastUiUpdateMs = 0;

    activeTransfer.value = TransferProgress(
      fileName: fileName,
      filePath: file.path,
      peerName: device.name,
      isSending: true,
      bytesTransferred: 0,
      totalBytes: totalBytes,
      speedBytesPerSec: 0,
      remainingSeconds: 0,
    );

    try {
      final request = await client.postUrl(
        Uri.parse('http://${device.ip}:${device.port}/upload'),
      );
      request.bufferOutput = false;
      request.contentLength = totalBytes;
      request.headers.set('x-file-name', Uri.encodeComponent(fileName));
      request.headers.set('x-sender-name', Uri.encodeComponent(deviceName));
      request.headers.set('x-file-size', totalBytes.toString());

      await for (final chunk in file.openRead()) {
        request.add(chunk);
        sentBytes += chunk.length;

        final elapsedMs = stopwatch.elapsedMilliseconds;
        if (elapsedMs - lastUiUpdateMs >= 100) {
          lastUiUpdateMs = elapsedMs;
          await request.flush();
          final speed =
              elapsedMs > 0 ? (sentBytes / (elapsedMs / 1000.0)) : 0.0;
          final remaining = (totalBytes > sentBytes && speed > 0)
              ? ((totalBytes - sentBytes) / speed).ceil()
              : 0;
          activeTransfer.value = TransferProgress(
            fileName: fileName,
            filePath: file.path,
            peerName: device.name,
            isSending: true,
            bytesTransferred: sentBytes,
            totalBytes: totalBytes,
            speedBytesPerSec: speed,
            remainingSeconds: remaining,
          );
        }
      }

      await request.flush();
      final response = await request.close().timeout(const Duration(minutes: 5));
      if (response.statusCode == 200) {
        activeTransfer.value = TransferProgress(
          fileName: fileName,
          filePath: file.path,
          peerName: device.name,
          isSending: true,
          bytesTransferred: totalBytes,
          totalBytes: totalBytes,
          speedBytesPerSec: 0,
          remainingSeconds: 0,
          isCompleted: true,
        );

        _transferController.add(TransferRecord(
          fileName: fileName,
          filePath: file.path,
          peerName: device.name,
          isSent: true,
          timestamp: DateTime.now(),
          sizeBytes: totalBytes,
        ));
        return true;
      } else {
        final serverMsg = await utf8.decoder.bind(response).join();
        errorReason = 'رد الجهاز الآخر (${response.statusCode}): $serverMsg';
      }
    } catch (e) {
      errorReason = e.toString().replaceAll('SocketException: ', '');
    } finally {
      client.close(force: true);
    }

    activeTransfer.value = TransferProgress(
      fileName: fileName,
      filePath: file.path,
      peerName: device.name,
      isSending: true,
      bytesTransferred: sentBytes,
      totalBytes: totalBytes,
      speedBytesPerSec: 0,
      remainingSeconds: 0,
      isFailed: true,
      errorMessage: errorReason,
    );
    return false;
  }

  Future<bool> sendChatToDevice(NetworkDevice device, String text) async {
    final client = _createBoundClient(
      device.ip,
      timeout: const Duration(seconds: 4),
    );
    try {
      final request = await client.postUrl(
        Uri.parse('http://${device.ip}:${device.port}/chat'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'sender': deviceName, 'text': text}));
      final response = await request.close();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
