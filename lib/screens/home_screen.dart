import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/device_model.dart';
import '../services/bluetooth_service.dart';
import '../services/network_service.dart';
import 'history_screen.dart';
import 'web_share_sheet.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDarkMode;

  const HomeScreen({
    super.key,
    required this.onToggleTheme,
    required this.isDarkMode,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final NetworkService _networkService = NetworkService();
  final BluetoothDiscoveryService _btService = BluetoothDiscoveryService();
  final TextEditingController _chatController = TextEditingController();

  List<NetworkDevice> _wifiDevices = [];
  final List<TransferRecord> _history = [];
  final List<ChatMessage> _messages = [];
  bool _isScanningWifi = false;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    await _networkService.startServer();
    _networkService.onTransfer.listen((rec) {
      if (mounted) {
        setState(() => _history.insert(0, rec));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(rec.isSent ? 'تم إرسال: ${rec.fileName}' : 'تم استلام: ${rec.fileName}')),
        );
      }
    });
    _networkService.onChat.listen((msg) {
      if (mounted) {
        setState(() => _messages.insert(0, msg));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('💬 ${msg.sender}: ${msg.text}')),
        );
      }
    });
    if (mounted) setState(() {});
    _scanWifiDevices();
  }

  @override
  void dispose() {
    _networkService.stopServer();
    _btService.dispose();
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _scanWifiDevices() async {
    if (_isScanningWifi) return;
    setState(() => _isScanningWifi = true);
    final devices = await _networkService.scanSubnet();
    if (mounted) {
      setState(() {
        _wifiDevices = devices;
        _isScanningWifi = false;
      });
    }
  }

  Future<void> _sendFilesToDevice(NetworkDevice device) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('جاري إرسال ${result.files.length} ملف إلى ${device.name}...')),
    );

    int successCount = 0;
    for (final f in result.files) {
      if (f.path != null) {
        final ok = await _networkService.sendFileToDevice(device, File(f.path!));
        if (ok) successCount++;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إرسال $successCount من ${result.files.length} ملف بنجاح ✅')),
      );
    }
  }

  Future<void> _sendGroupFiles() async {
    if (_wifiDevices.isEmpty) {
      _openSendDiscoverySheet();
      return;
    }
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    for (final device in _wifiDevices) {
      for (final f in result.files) {
        if (f.path != null) {
          await _networkService.sendFileToDevice(device, File(f.path!));
        }
      }
    }
  }

  Future<void> _sendChat() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    _chatController.clear();
    setState(() {
      _messages.insert(
        0,
        ChatMessage(
          sender: _networkService.deviceName,
          text: text,
          timestamp: DateTime.now(),
          isMe: true,
        ),
      );
    });
    for (final dev in _wifiDevices) {
      await _networkService.sendChatToDevice(dev, text);
    }
  }

  void _openSendDiscoverySheet() {
    _scanWifiDevices();
    _btService.startScan();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DefaultTabController(
          length: 2,
          child: SafeArea(
            top: false,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.72,
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'البحث عن الأجهزة القريبة',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  const TabBar(
                    tabs: [
                      Tab(icon: Icon(Icons.wifi), text: 'الشبكة (تلقائي)'),
                      Tab(icon: Icon(Icons.bluetooth_searching), text: 'بلوتوث قريب'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Tab 1: Auto Wi-Fi / Hotspot Scan
                        StatefulBuilder(
                          builder: (context, setModalState) {
                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _isScanningWifi
                                            ? 'جاري فحص الشبكة تلقائياً...'
                                            : 'الأجهزة المتاحة (${_wifiDevices.length})',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      TextButton.icon(
                                        onPressed: () async {
                                          setModalState(() {});
                                          await _scanWifiDevices();
                                          setModalState(() {});
                                        },
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('تحديث'),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_isScanningWifi)
                                  const LinearProgressIndicator(),
                                Expanded(
                                  child: _wifiDevices.isEmpty
                                      ? const Center(
                                          child: Text(
                                           'لا توجد أجهزة PulseDrop على نفس الشبكة حالياً.\nتأكد أن الجهازين على نفس الواي فاي أو الهوتسبوت.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(color: Colors.grey),
                                          ),
                                        )
                                      : ListView.builder(
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          itemCount: _wifiDevices.length,
                                          itemBuilder: (_, i) {
                                            final dev = _wifiDevices[i];
                                            return Card(
                                              child: ListTile(
                                                leading: const CircleAvatar(
                                                  backgroundColor: Color(0xFF0EA5E9),
                                                  child: Icon(Icons.smartphone, color: Colors.white),
                                                ),
                                                title: Text(dev.name),
                                                subtitle: Text(dev.ip),
                                                trailing: FilledButton(
                                                  onPressed: () {
                                                    Navigator.pop(ctx);
                                                    _sendFilesToDevice(dev);
                                                  },
                                                  child: const Text('إرسال'),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: TextButton(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _showManualIpDialog();
                                    },
                                    child: const Text('إدخال IP يدوياً (خيار احتياطي)'),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        // Tab 2: Nearby Bluetooth Scan
                        StreamBuilder<List<BluetoothDeviceItem>>(
                          stream: _btService.devicesStream,
                          initialData: const [],
                          builder: (context, snapshot) {
                            final btDevices = snapshot.data ?? [];
                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'أجهزة البلوتوث القريبة (${btDevices.length})',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      TextButton.icon(
                                        onPressed: () => _btService.startScan(),
                                        icon: const Icon(Icons.bluetooth_searching),
                                        label: const Text('بحث مجدداً'),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: btDevices.isEmpty
                                      ? const Center(
                                          child: Text(
                                            'جاري البحث عن أجهزة البلوتوث القريبة...\nتأكد من تفعيل البلوتوث والموقع.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(color: Colors.grey),
                                          ),
                                        )
                                      : ListView.builder(
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          itemCount: btDevices.length,
                                          itemBuilder: (_, i) {
                                            final b = btDevices[i];
                                            return Card(
                                              child: ListTile(
                                                leading: const CircleAvatar(
                                                  backgroundColor: Color(0xFF2563EB),
                                                  child: Icon(Icons.bluetooth, color: Colors.white),
                                                ),
                                                title: Text(b.name),
                                                subtitle: Text('قوة الإشارة: ${b.rssi} dBm'),
                                                trailing: const Icon(Icons.chevron_left),
                                                onTap: () {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'تم العثور على ${b.name} — افتح الهوتسبوت للنقل بأقصى سرعة',
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(() => _btService.stopScan());
  }

  void _showManualIpDialog() {
    final ipCtrl = TextEditingController(text: '192.168.1.');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إدخال IP يدوياً'),
        content: TextField(
          controller: ipCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '192.168.1.5',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final ip = ipCtrl.text.trim();
              Navigator.pop(ctx);
              if (ip.isNotEmpty) {
                _sendFilesToDevice(NetworkDevice(name: 'جهاز ($ip)', ip: ip));
              }
            },
            child: const Text('اتصال وإرسال'),
          ),
        ],
      ),
    );
  }

  void _openWebShareSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WebShareSheet(
        networkService: _networkService,
        onQrIpScanned: (ip) {
          _sendFilesToDevice(NetworkDevice(name: 'جهاز QR ($ip)', ip: ip));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ip = _networkService.localIp ?? 'جاري تحديد IP...';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0EA5E9), Color(0xFF2563EB)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.bolt, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PulseDrop',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                Text(
                  _networkService.isVisible ? 'الرادار نشط' : 'وضع التخفي',
                  style: TextStyle(
                    fontSize: 12,
                    color: _networkService.isVisible ? Colors.teal : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _networkService.isVisible ? Icons.visibility : Icons.visibility_off,
            ),
            onPressed: () {
              setState(() {
                _networkService.isVisible = !_networkService.isVisible;
              });
            },
          ),
          IconButton(
            icon: Icon(widget.isDarkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      body: Column(
        children: [
          // Local Chat Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _chatController,
              decoration: InputDecoration(
                hintText: 'شات محلي: اكتب نص أو رابط...',
                filled: true,
                fillColor: Theme.of(context).cardColor,
                prefixIcon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF0EA5E9)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send_rounded, color: Color(0xFF4F46E5)),
                  onPressed: _sendChat,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _sendChat(),
            ),
          ),

          // Group Send Button
          OutlinedButton.icon(
            onPressed: _sendGroupFiles,
            icon: const Icon(Icons.hub_outlined),
            label: const Text('إرسال جماعي'),
          ),

          // Radar Area
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _scanWifiDevices,
                    child: Container(
                      width: 170,
                      height: 170,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF0EA5E9).withOpacity(0.25),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 110,
                          height: 110,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Color(0xFF0EA5E9), Color(0xFF3B82F6)],
                            ),
                          ),
                          child: const Icon(Icons.bolt, color: Colors.white, size: 48),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _networkService.deviceName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    ip,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (_isScanningWifi)
                    const Text('جاري البحث التلقائي عن الأجهزة القريبة...')
                  else if (_wifiDevices.isEmpty)
                    const Text(
                      'اضغط على الرادار أو "إرسال" للبحث التلقائي بالواي فاي والبلوتوث',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: _wifiDevices.map((dev) {
                        return ActionChip(
                          avatar: const Icon(Icons.smartphone, size: 18),
                          label: Text(dev.name),
                          onPressed: () => _sendFilesToDevice(dev),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      // Bottom Bar protected with SafeArea so Android navigation buttons never overlap!
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: _openSendDiscoverySheet,
                icon: const Icon(Icons.send_rounded),
                label: const Text('إرسال'),
              ),
              FloatingActionButton(
                elevation: 2,
                onPressed: _openWebShareSheet,
                backgroundColor: const Color(0xFF0EA5E9),
                child: const Icon(Icons.qr_code_2, color: Colors.white, size: 28),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HistoryScreen(records: _history),
                    ),
                  );
                },
                icon: const Icon(Icons.history),
                label: const Text('السجل'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
