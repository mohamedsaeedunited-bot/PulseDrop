import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../models/device_model.dart';

class NetworkService {
  static const int serverPort = 8080;
  HttpServer? _server;
  String deviceName = 'PulseDrop Phone';
  String? localIp;
  bool isVisible = true;

  final List<File> sharedWebFiles = [];
  final StreamController<TransferRecord> _transferController =
      StreamController<TransferRecord>.broadcast();
  final StreamController<ChatMessage> _chatController =
      StreamController<ChatMessage>.broadcast();

  Stream<TransferRecord> get onTransfer => _transferController.stream;
  Stream<ChatMessage> get onChat => _chatController.stream;

  Future<String?> getLocalIpAddress() async {
    try {
      final info = NetworkInfo();
      String? ip = await info.getWifiIP();
      if (ip != null && ip.isNotEmpty && ip != '0.0.0.0') {
        localIp = ip;
        return ip;
      }
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback &&
              (addr.address.startsWith('192.168.') ||
                  addr.address.startsWith('10.') ||
                  addr.address.startsWith('172.'))) {
            localIp = addr.address;
            return localIp;
          }
        }
      }
    } catch (_) {}
    return localIp;
  }

  Future<void> startServer() async {
    if (_server != null) return;
    await getLocalIpAddress();
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, serverPort, shared: true);
      _server!.listen(_handleRequest);
    } catch (_) {}
  }

  Future<void> stopServer() async {
    await _server?.close(force: true);
    _server = null;
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
        'version': '4.0',
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
      final fileName = Uri.decodeComponent(rawName);
      final senderName = Uri.decodeComponent(
        request.headers.value('x-sender-name') ?? 'جهاز قريب',
      );

      final dir = await _getDownloadDirectory();
      final saveFile = File('${dir.path}/$fileName');
      final sink = saveFile.openWrite();
      int totalBytes = 0;
      await for (final chunk in request) {
        totalBytes += chunk.length;
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();

      _transferController.add(TransferRecord(
        fileName: fileName,
        filePath: saveFile.path,
        peerName: senderName,
        isSent: false,
        timestamp: DateTime.now(),
        sizeBytes: totalBytes,
      ));

      request.response.statusCode = HttpStatus.ok;
      request.response.write('UPLOADED');
      await request.response.close();
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

    // Web Portal UI
    request.response.headers.contentType = ContentType.html;
    request.response.write(_buildWebPortalHtml());
    await request.response.close();
  }

  Future<Directory> _getDownloadDirectory() async {
    try {
      final extDir = Directory('/storage/emulated/0/Download/PulseDrop');
      if (!await extDir.exists()) {
        await extDir.create(recursive: true);
      }
      return extDir;
    } catch (_) {
      final appDir = await getApplicationDocumentsDirectory();
      final fallback = Directory('${appDir.path}/PulseDrop');
      if (!await fallback.exists()) {
        await fallback.create(recursive: true);
      }
      return fallback;
    }
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

  /// Fast Subnet Auto-Discovery (scans all 254 IPs in parallel batches)
  Future<List<NetworkDevice>> scanSubnet() async {
    final ip = await getLocalIpAddress();
    if (ip == null || !ip.contains('.')) return [];

    final parts = ip.split('.');
    if (parts.length != 4) return [];
    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';

    final List<NetworkDevice> found = [];
    const batchSize = 32;

    for (int start = 1; start <= 254; start += batchSize) {
      final futures = <Future<void>>[];
      for (int i = start; i < start + batchSize && i <= 254; i++) {
        final targetIp = '$subnet.$i';
        if (targetIp == ip) continue;
        futures.add(_probeDevice(targetIp, found));
      }
      await Future.wait(futures);
    }
    return found;
  }

  Future<void> _probeDevice(String targetIp, List<NetworkDevice> found) async {
    try {
      final response = await http
          .get(Uri.parse('http://$targetIp:$serverPort/ping'))
          .timeout(const Duration(milliseconds: 550));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['app'] == 'PulseDrop') {
          found.add(NetworkDevice(
            name: data['name'] ?? 'PulseDrop Device',
            ip: targetIp,
            port: serverPort,
            version: data['version'] ?? '4.0',
          ));
        }
      }
    } catch (_) {}
  }

  Future<bool> sendFileToDevice(NetworkDevice device, File file) async {
    try {
      final fileName = file.path.split('/').last;
      final bytes = await file.readAsBytes();
      final response = await http
          .post(
            Uri.parse('http://${device.ip}:${device.port}/upload'),
            headers: {
              'x-file-name': Uri.encodeComponent(fileName),
              'x-sender-name': Uri.encodeComponent(deviceName),
            },
            body: bytes,
          )
          .timeout(const Duration(minutes: 5));

      if (response.statusCode == 200) {
        _transferController.add(TransferRecord(
          fileName: fileName,
          filePath: file.path,
          peerName: device.name,
          isSent: true,
          timestamp: DateTime.now(),
          sizeBytes: bytes.length,
        ));
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> sendChatToDevice(NetworkDevice device, String text) async {
    try {
      final response = await http
          .post(
            Uri.parse('http://${device.ip}:${device.port}/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'sender': deviceName, 'text': text}),
          )
          .timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
