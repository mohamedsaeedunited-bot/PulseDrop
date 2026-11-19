import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class TransferEngine extends ChangeNotifier {
  static const int serverPort = 53317;
  HttpServer? _server;
  bool isRunning = false;

  String deviceName = 'PulseDrop';
  bool pinEnabled = false;
  String webPin = '4829';
  bool autoAccept = true;

  final List<TransferTask> activeTasks = [];
  final List<TransferTask> history = [];
  final List<SharedFileItem> webSharedFiles = [];
  final List<ChatMessage> chatMessages = [];

  int get totalBytesTransferred =>
      history.fold<int>(0, (sum, item) => sum + item.totalBytes);

  Future<void> init(String name) async {
    deviceName = name;
    final prefs = await SharedPreferences.getInstance();
    pinEnabled = prefs.getBool('pin_enabled') ?? false;
    autoAccept = prefs.getBool('auto_accept') ?? true;
    webPin = prefs.getString('web_pin') ?? (1000 + Random().nextInt(9000)).toString();
    await prefs.setString('web_pin', webPin);
    await _loadHistory();
    await startServer();
  }

  Future<void> setPinEnabled(bool val) async {
    pinEnabled = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pin_enabled', val);
    notifyListeners();
  }

  Future<void> setAutoAccept(bool val) async {
    autoAccept = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_accept', val);
    notifyListeners();
  }

  Future<void> regeneratePin() async {
    webPin = (1000 + Random().nextInt(9000)).toString();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('web_pin', webPin);
    notifyListeners();
  }

  Future<void> startServer() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, serverPort, shared: true);
      isRunning = true;
      notifyListeners();
      _server!.listen(_handleRequest);
    } catch (e) {
      debugPrint('Server start error: $e');
      isRunning = false;
      notifyListeners();
    }
  }

  void addWebSharedFiles(List<SharedFileItem> items) {
    webSharedFiles.addAll(items);
    notifyListeners();
  }

  void clearWebSharedFiles() {
    webSharedFiles.clear();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    history.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pulsedrop_history');
    notifyListeners();
  }

  Future<Directory> _getReceiveDirectory(String fileName) async {
    final ext = fileName.split('.').last.toLowerCase();
    String sub = 'Others';
    if (['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic'].contains(ext)) {
      sub = 'Images';
    } else if (['mp4', 'mkv', 'mov', 'avi', 'webm'].contains(ext)) {
      sub = 'Videos';
    } else if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'ppt', 'pptx'].contains(ext)) {
      sub = 'Documents';
    } else if (['apk', 'xapk'].contains(ext)) {
      sub = 'Apps';
    }

    Directory? baseDir;
    if (Platform.isAndroid) {
      final downloadDir = Directory('/storage/emulated/0/Download/PulseDrop/$sub');
      try {
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        return downloadDir;
      } catch (_) {
        baseDir = await getExternalStorageDirectory();
      }
    }
    baseDir ??= await getApplicationDocumentsDirectory();
    final pulseDir = Directory('${baseDir.path}/PulseDrop/$sub');
    if (!await pulseDir.exists()) {
      await pulseDir.create(recursive: true);
    }
    return pulseDir;
  }

  bool _checkPin(HttpRequest req) {
    if (!pinEnabled) return true;
    final provided = req.headers.value('x-pin') ?? req.uri.queryParameters['pin'] ?? '';
    return provided == webPin;
  }

  Future<void> _handleRequest(HttpRequest req) async {
    req.response.headers.add('Access-Control-Allow-Origin', '*');
    req.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    req.response.headers.add('Access-Control-Allow-Headers', '*');

    if (req.method == 'OPTIONS') {
      req.response.statusCode = HttpStatus.ok;
      await req.response.close();
      return;
    }

    final path = req.uri.path;

    if (req.method == 'GET' && path == '/') {
      req.response.headers.contentType = ContentType.html;
      req.response.write(_buildWebPortalHtml());
      await req.response.close();
      return;
    }

    if (req.method == 'GET' && path == '/api/info') {
      if (!_checkPin(req)) {
        req.response.statusCode = HttpStatus.unauthorized;
        req.response.write(jsonEncode({'pinRequired': true}));
        await req.response.close();
        return;
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({
        'app': 'PulseDrop',
        'name': deviceName,
        'pinRequired': pinEnabled,
        'files': webSharedFiles
            .map((f) => {'id': f.id, 'name': f.name, 'size': f.size, 'isVideo': f.isVideo})
            .toList(),
      }));
      await req.response.close();
      return;
    }

    if (req.method == 'GET' && (path.startsWith('/api/download/') || path.startsWith('/api/stream/'))) {
      if (!_checkPin(req)) {
        req.response.statusCode = HttpStatus.unauthorized;
        await req.response.close();
        return;
      }
      final isStream = path.startsWith('/api/stream/');
      final id = path.replaceFirst(isStream ? '/api/stream/' : '/api/download/', '');
      final match = webSharedFiles.where((f) => f.id == id).toList();
      if (match.isEmpty) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }
      final item = match.first;
      final file = File(item.path);
      if (!await file.exists()) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }
      final length = await file.length();
      if (isStream) {
        req.response.headers.set('Content-Type', 'video/mp4');
        req.response.headers.set('Accept-Ranges', 'bytes');
        req.response.headers.set('Content-Length', length);
      } else {
        final encodedName = Uri.encodeComponent(item.name);
        req.response.headers.set('Content-Type', 'application/octet-stream');
        req.response.headers.set('Content-Disposition', "attachment; filename*=UTF-8''$encodedName");
        req.response.headers.set('Content-Length', length);
      }
      await req.response.addStream(file.openRead());
      await req.response.close();
      return;
    }

    if (req.method == 'POST' && path == '/api/clip') {
      try {
        final body = await utf8.decoder.bind(req).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final text = data['text']?.toString() ?? '';
        final sender = data['sender']?.toString() ?? 'Device';
        if (text.isNotEmpty) {
          chatMessages.insert(
            0,
            ChatMessage(text: text, sender: sender, isMe: false, timestamp: DateTime.now()),
          );
          notifyListeners();
        }
        req.response.statusCode = HttpStatus.ok;
        req.response.write(jsonEncode({'ok': true}));
      } catch (e) {
        req.response.statusCode = HttpStatus.badRequest;
      }
      await req.response.close();
      return;
    }

    if (req.method == 'POST' && path == '/api/upload') {
      await _handleFileUpload(req);
      return;
    }

    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }

  Future<void> _handleFileUpload(HttpRequest req) async {
    final rawName = req.headers.value('x-file-name') ??
        req.uri.queryParameters['name'] ??
        'file_${DateTime.now().millisecondsSinceEpoch}';
    final fileName = Uri.decodeComponent(rawName);
    final peerName = Uri.decodeComponent(req.headers.value('x-sender-name') ?? 'Web / Peer');
    final totalBytes = req.contentLength > 0
        ? req.contentLength
        : (int.tryParse(req.headers.value('x-file-size') ?? '0') ?? 0);

    final dir = await _getReceiveDirectory(fileName);
    String safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    File outFile = File('${dir.path}/$safeName');
    if (await outFile.exists()) {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      outFile = File('${dir.path}/${stamp}_$safeName');
    }

    final task = TransferTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      fileName: fileName,
      filePath: outFile.path,
      totalBytes: totalBytes,
      direction: TransferDirection.receive,
      timestamp: DateTime.now(),
      peerName: peerName,
    );
    activeTasks.insert(0, task);
    notifyListeners();

    final sink = outFile.openWrite();
    final stopwatch = Stopwatch()..start();
    int received = 0;
    int lastNotifyMs = 0;

    try {
      await for (final chunk in req) {
        sink.add(chunk);
        received += chunk.length;
        task.transferredBytes = received;

        final elapsedMs = stopwatch.elapsedMilliseconds;
        if (elapsedMs - lastNotifyMs >= 180) {
          task.speedBytesPerSec = elapsedMs > 0 ? (received / (elapsedMs / 1000.0)) : 0;
          lastNotifyMs = elapsedMs;
          notifyListeners();
        }
      }
      await sink.flush();
      await sink.close();

      task.status = TransferStatus.completed;
      if (task.totalBytes <= 0) task.transferredBytes = received;
      _finishTask(task);

      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'ok': true, 'saved': outFile.path}));
      await req.response.close();
    } catch (e) {
      await sink.close();
      task.status = TransferStatus.failed;
      _finishTask(task);
      req.response.statusCode = HttpStatus.internalServerError;
      await req.response.close();
    }
  }

  Future<bool> sendFileToPeer({
    required String ip,
    required int port,
    required String peerName,
    required File file,
    required String fileName,
  }) async {
    final totalBytes = await file.length();
    final task = TransferTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      fileName: fileName,
      filePath: file.path,
      totalBytes: totalBytes,
      direction: TransferDirection.send,
      timestamp: DateTime.now(),
      peerName: peerName,
    );
    activeTasks.insert(0, task);
    notifyListeners();

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final uri = Uri.parse('http://$ip:$port/api/upload');
      final request = await client.postUrl(uri);
      request.headers.set('Content-Type', 'application/octet-stream');
      request.headers.set('Content-Length', totalBytes);
      request.headers.set('x-file-name', Uri.encodeComponent(fileName));
      request.headers.set('x-sender-name', Uri.encodeComponent(deviceName));
      request.headers.set('x-file-size', totalBytes.toString());

      final stopwatch = Stopwatch()..start();
      int sent = 0;
      int lastNotifyMs = 0;

      await for (final chunk in file.openRead()) {
        request.add(chunk);
        sent += chunk.length;
        task.transferredBytes = sent;

        final elapsedMs = stopwatch.elapsedMilliseconds;
        if (elapsedMs - lastNotifyMs >= 180) {
          task.speedBytesPerSec = elapsedMs > 0 ? (sent / (elapsedMs / 1000.0)) : 0;
          lastNotifyMs = elapsedMs;
          notifyListeners();
        }
      }

      final response = await request.close();
      await response.drain();
      client.close();

      if (response.statusCode == 200) {
        task.status = TransferStatus.completed;
        _finishTask(task);
        return true;
      } else {
        task.status = TransferStatus.failed;
        _finishTask(task);
        return false;
      }
    } catch (e) {
      client.close(force: true);
      task.status = TransferStatus.failed;
      _finishTask(task);
      return false;
    }
  }

  Future<bool> sendChatToPeer({
    required String ip,
    required int port,
    required String text,
  }) async {
    chatMessages.insert(
      0,
      ChatMessage(text: text, sender: deviceName, isMe: true, timestamp: DateTime.now()),
    );
    notifyListeners();

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(Uri.parse('http://$ip:$port/api/clip'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'text': text, 'sender': deviceName}));
      final response = await request.close();
      await response.drain();
      client.close();
      return response.statusCode == 200;
    } catch (_) {
      client.close(force: true);
      return false;
    }
  }

  void _finishTask(TransferTask task) {
    history.insert(0, task);
    if (history.length > 150) history.removeLast();
    _saveHistory();
    notifyListeners();
    Future.delayed(const Duration(seconds: 4), () {
      activeTasks.remove(task);
      notifyListeners();
    });
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('pulsedrop_history');
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      history.clear();
      history.addAll(list.map((e) => TransferTask.fromJson(e as Map<String, dynamic>)));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(history.map((e) => e.toJson()).toList());
    await prefs.setString('pulsedrop_history', raw);
  }

  String _buildWebPortalHtml() {
    return '''<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>PulseDrop Web Share & Stream</title>
<style>
  :root { --primary:#4F46E5; --accent:#06B6D4; --bg:#F8FAFC; --card:#FFFFFF; --text:#0F172A; --sub:#64748B; --border:#E2E8F0; }
  * { box-sizing:border-box; font-family: system-ui, -apple-system, sans-serif; }
  body { margin:0; background:var(--bg); color:var(--text); padding:20px; }
  .wrap { max-width:680px; margin:0 auto; }
  .header { display:flex; align-items:center; justify-content:space-between; margin-bottom:20px; }
  .brand { font-size:24px; font-weight:800; background:linear-gradient(135deg,var(--primary),var(--accent)); -webkit-background-clip:text; -webkit-text-fill-color:transparent; }
  .badge { background:#EEF2FF; color:var(--primary); padding:6px 14px; border-radius:99px; font-size:13px; font-weight:600; }
  .card { background:var(--card); border:1px solid var(--border); border-radius:20px; padding:20px; margin-bottom:16px; box-shadow:0 4px 20px rgba(15,23,42,0.04); }
  .dropzone { border:2px dashed #CBD5E1; border-radius:16px; padding:30px 16px; text-align:center; cursor:pointer; }
  .btn { background:var(--primary); color:#fff; border:none; padding:10px 16px; border-radius:12px; font-weight:600; cursor:pointer; font-size:13px; text-decoration:none; }
  .btn-cyan { background:var(--accent); }
  .row { display:flex; gap:10px; align-items:center; }
  input[type=text], input[type=password] { flex:1; padding:12px 14px; border:1px solid var(--border); border-radius:12px; font-size:14px; outline:none; }
  .file-item { display:flex; justify-content:space-between; align-items:center; gap:8px; padding:12px 0; border-bottom:1px solid var(--border); }
  .file-item:last-child { border-bottom:none; }
  video { width:100%; border-radius:14px; margin-top:12px; display:none; background:#000; }
  #pinBox { display:none; }
</style>
</head>
<body>
<div class="wrap">
  <div class="header">
    <div class="brand">PulseDrop v3</div>
    <div class="badge" id="devName">متصل بالموبايل</div>
  </div>

  <div class="card" id="pinBox">
    <h3 style="margin-top:0">🔐 أدخل الرقم السري (PIN) الظاهر على الموبايل</h3>
    <div class="row">
      <input type="password" id="pinInput" placeholder="4 أرقام...">
      <button class="btn" onclick="unlockPin()">دخول</button>
    </div>
  </div>

  <div id="mainContent">
    <div class="card">
      <h3 style="margin-top:0">⚡ إرسال ملفات للموبايل</h3>
      <div class="dropzone" onclick="document.getElementById('fileInput').click()">
        <div style="font-weight:700;margin-bottom:4px">اضغط لاختيار ملفات من جهازك</div>
        <div style="font-size:13px;color:var(--sub)">نقل مباشر على الواي فاي بأقصى سرعة بدون نت</div>
        <input type="file" id="fileInput" multiple style="display:none" onchange="uploadFiles(this.files)">
      </div>
      <div id="progText" style="margin-top:10px;font-size:13px;color:var(--primary);font-weight:600"></div>
    </div>

    <div class="card">
      <h3 style="margin-top:0">💬 شات محلي سريع</h3>
      <div class="row">
        <input type="text" id="clipInput" placeholder="اكتب رسالة أو الصق رابط...">
        <button class="btn btn-cyan" onclick="sendClip()">إرسال</button>
      </div>
    </div>

    <div class="card">
      <h3 style="margin-top:0">🎬 ملفات جاهزة للتحميل أو البث المباشر</h3>
      <div id="fileList" style="color:var(--sub);font-size:14px">جاري التحميل...</div>
      <video id="streamPlayer" controls></video>
    </div>
  </div>
</div>

<script>
let currentPin = '';
function unlockPin() {
  currentPin = document.getElementById('pinInput').value.trim();
  loadInfo();
}
async function loadInfo() {
  try {
    const r = await fetch('/api/info?pin=' + encodeURIComponent(currentPin));
    if (r.status === 401) {
      document.getElementById('pinBox').style.display = 'block';
      document.getElementById('mainContent').style.display = 'none';
      return;
    }
    document.getElementById('pinBox').style.display = 'none';
    document.getElementById('mainContent').style.display = 'block';
    const d = await r.json();
    document.getElementById('devName').textContent = d.name;
    const list = document.getElementById('fileList');
    if (!d.files || d.files.length === 0) {
      list.innerHTML = 'لم يتم اختيار ملفات من الموبايل بعد.';
      return;
    }
    list.innerHTML = d.files.map(f => {
      const q = '?pin=' + encodeURIComponent(currentPin);
      const streamBtn = f.isVideo ? '<button class="btn btn-cyan" onclick="playStream(\'' + f.id + '\')">بث مباشر ▶</button>' : '';
      return '<div class="file-item"><div><b>' + f.name + '</b><div style="font-size:12px;color:#64748B">' +
        (f.size / (1024*1024)).toFixed(2) + ' MB</div></div><div class="row">' + streamBtn +
        '<a class="btn" href="/api/download/' + f.id + q + '">تحميل</a></div></div>';
    }).join('');
  } catch (e) {}
}
function playStream(id) {
  const v = document.getElementById('streamPlayer');
  v.src = '/api/stream/' + id + '?pin=' + encodeURIComponent(currentPin);
  v.style.display = 'block';
  v.play();
}
function uploadFiles(files) {
  const arr = Array.from(files);
  let idx = 0;
  function next() {
    if (idx >= arr.length) {
      document.getElementById('progText').textContent = 'تم إرسال جميع الملفات بنجاح ✓';
      return;
    }
    const file = arr[idx++];
    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/api/upload', true);
    xhr.setRequestHeader('x-file-name', encodeURIComponent(file.name));
    xhr.setRequestHeader('x-sender-name', encodeURIComponent('Web Browser'));
    xhr.setRequestHeader('x-file-size', file.size);
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) {
        const pct = Math.round((e.loaded / e.total) * 100);
        document.getElementById('progText').textContent = file.name + ' — ' + pct + '%';
      }
    };
    xhr.onload = () => next();
    xhr.onerror = () => next();
    xhr.send(file);
  }
  next();
}
async function sendClip() {
  const input = document.getElementById('clipInput');
  if (!input.value.trim()) return;
  await fetch('/api/clip', {
    method: 'POST',
    headers: {'Content-Type':'application/json'},
    body: JSON.stringify({text: input.value.trim(), sender: 'Web Browser'})
  });
  input.value = '';
  alert('تم الإرسال ✓');
}
loadInfo();
setInterval(loadInfo, 5000);
</script>
</body>
</html>''';
  }

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }
}
