import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_model.dart';
import '../services/bluetooth_service.dart';
import '../services/network_service.dart';
import '../widgets/transfer_progress_card.dart';
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

  final List<TransferRecord> _history = [];
  final List<ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadSavedHistory();
    _initServices();
  }

  Future<void> _loadSavedHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList('pulsedrop_history') ?? [];
      if (mounted) {
        setState(() {
          _history.clear();
          for (final item in rawList) {
            _history.add(TransferRecord.fromJson(jsonDecode(item)));
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = _history.take(100).map((r) => jsonEncode(r.toJson())).toList();
      await prefs.setStringList('pulsedrop_history', encoded);
    } catch (_) {}
  }

  Future<void> _initServices() async {
    await _networkService.startServices();
    _networkService.onTransfer.listen((rec) {
      if (mounted) {
        setState(() => _history.insert(0, rec));
        _saveHistory();
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
  }

  @override
  void dispose() {
    _networkService.stopServices();
    _btService.dispose();
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _sendFilesToDevice(NetworkDevice device) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    for (final f in result.files) {
      if (f.path != null) {
        await _networkService.sendFileToDevice(device, File(f.path!));
      }
    }
  }

  Future<void> _sendGroupFiles() async {
    final devices = _networkService.discoveredDevices.value;
    if (devices.isEmpty) {
      _openSendDiscoverySheet();
      return;
    }
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    for (final device in devices) {
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
    for (final dev in _networkService.discoveredDevices.value) {
      await _networkService.sendChatToDevice(dev, text);
    }
  }

  void _showRenameDeviceDialog() {
    final ctrl = TextEditingController(text: _networkService.deviceName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تغيير اسم جهازك'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'اكتب اسم الموبايل...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              Navigator.pop(ctx);
              if (name.isNotEmpty) {
                await _networkService.saveDeviceName(name);
                if (mounted) setState(() {});
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _openSendDiscoverySheet() {
    _networkService.startAutoDiscovery();
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
              height: MediaQuery.of(context).size.height * 0.74,
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
                    'البحث التلقائي عن الأجهزة القريبة',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const TabBar(
                    tabs: [
                      Tab(icon: Icon(Icons.wifi), text: 'الواي فاي والهوتسبوت'),
                      Tab(icon: Icon(Icons.bluetooth_searching), text: 'بلوتوث قريب'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        ValueListenableBuilder<List<NetworkDevice>>(
                          valueListenable: _networkService.discoveredDevices,
                          builder: (context, devices, _) {
                            return ValueListenableBuilder<bool>(
                              valueListenable: _networkService.isScanning,
                              builder: (context, scanning, _) {
                                return Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            scanning
                                                ? 'جاري البحث التلقائي في الشبكة...'
                                                : 'الأجهزة المتاحة (${devices.length})',
                                            style: const TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                          TextButton.icon(
                                            onPressed: () => _networkService.startAutoDiscovery(),
                                            icon: const Icon(Icons.refresh),
                                            label: const Text('تحديث'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (scanning) const LinearProgressIndicator(),
                                    Expanded(
                                      child: devices.isEmpty
                                          ? const Center(
                                              child: Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 24),
                                                child: Text(
                                                  'لا توجد أجهزة PulseDrop متصلة حالياً.\nتأكد أن الجهاز الآخر فاتح تطبيق PulseDrop على نفس الواي فاي أو الهوتسبوت.',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(color: Colors.grey, height: 1.5),
                                                ),
                                              ),
                                            )
                                          : ListView.builder(
                                              padding: const EdgeInsets.symmetric(horizontal: 12),
                                              itemCount: devices.length,
                                              itemBuilder: (_, i) {
                                                final dev = devices[i];
                                                return Card(
                                                  child: ListTile(
                                                    leading: const CircleAvatar(
                                                      backgroundColor: Color(0xFF0EA5E9),
                                                      child: Icon(Icons.smartphone, color: Colors.white),
                                                    ),
                                                    title: Text(
                                                      dev.name,
                                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                                    ),
                                                    subtitle: Text(dev.ip),
                                                    trailing: FilledButton.icon(
                                                      onPressed: () {
                                                        Navigator.pop(ctx);
                                                        _sendFilesToDevice(dev);
                                                      },
                                                      icon: const Icon(Icons.send, size: 16),
                                                      label: const Text('إرسال'),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(10),
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
                            );
                          },
                        ),
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
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 24),
                                            child: Text(
                                              'جاري البحث عن الموبايلات القريبة بالبلوتوث...\nتأكد من تفعيل البلوتوث والموقع (Location) على الجهازين.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(color: Colors.grey, height: 1.5),
                                            ),
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
                                                title: Text(
                                                  b.name,
                                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                                ),
                                                subtitle: Text(b.signalLabel),
                                                trailing: const Icon(Icons.chevron_left),
                                                onTap: () {
                                                  Navigator.pop(ctx);
                                                  _openWebShareSheet();
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'تم رصد "${b.name}" — افتح الهوتسبوت أو امسح QR للنقل بأقصى سرعة',
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
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'تغيير اسم الجهاز',
            onPressed: _showRenameDeviceDialog,
          ),
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
          ValueListenableBuilder<TransferProgress?>(
            valueListenable: _networkService.activeTransfer,
            builder: (context, progress, _) {
              if (progress == null) return const SizedBox.shrink();
              return TransferProgressCard(
                transfer: progress,
                onDismiss: () => _networkService.activeTransfer.value = null,
                onPreview: progress.filePath != null
                    ? () => OpenFilex.open(progress.filePath!)
                    : null,
              );
            },
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _sendGroupFiles,
                  icon: const Icon(Icons.hub_outlined, size: 18),
                  label: const Text('إرسال جماعي'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HistoryScreen(
                          records: _history,
                          onClearHistory: () {
                            setState(() => _history.clear());
                            _saveHistory();
                          },
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.folder_copy_outlined, size: 18),
                  label: Text('الملفات (${_history.length})'),
                ),
              ],
            ),
          ),

          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => _networkService.startAutoDiscovery(),
                      child: Container(
                        width: 158,
                        height: 158,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF0EA5E9).withOpacity(0.25),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 104,
                            height: 104,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [Color(0xFF0EA5E9), Color(0xFF3B82F6)],
                              ),
                            ),
                            child: const Icon(Icons.bolt, color: Colors.white, size: 46),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _showRenameDeviceDialog,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _networkService.deviceName,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.edit, size: 14, color: Colors.grey),
                        ],
                      ),
                    ),
                    Text(
                      ip,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    ValueListenableBuilder<List<NetworkDevice>>(
                      valueListenable: _networkService.discoveredDevices,
                      builder: (context, devices, _) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: _networkService.isScanning,
                          builder: (context, scanning, _) {
                            if (devices.isNotEmpty) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.center,
                                  children: devices.map((dev) {
                                    return ActionChip(
                                      avatar: const Icon(
                                        Icons.smartphone,
                                        size: 18,
                                        color: Color(0xFF0284C7),
                                      ),
                                      label: Text(
                                        dev.name,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      onPressed: () => _sendFilesToDevice(dev),
                                    );
                                  }).toList(),
                                ),
                              );
                            }
                            if (scanning) {
                              return const Text(
                                'جاري البحث التلقائي عن الأجهزة القريبة...',
                                style: TextStyle(color: Color(0xFF0284C7), fontSize: 13),
                              );
                            }
                            return const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                'اضغط على الرادار أو "إرسال" للبحث التلقائي بالواي فاي والبلوتوث',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey, fontSize: 13),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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
                      builder: (_) => HistoryScreen(
                        records: _history,
                        onClearHistory: () {
                          setState(() => _history.clear());
                          _saveHistory();
                        },
                      ),
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
