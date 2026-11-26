import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_model.dart';
import '../services/bluetooth_service.dart';
import '../services/network_service.dart';
import '../services/update_service.dart';
import '../widgets/transfer_progress_card.dart';
import 'history_screen.dart';
import 'qr_scanner_screen.dart';
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final NetworkService _networkService = NetworkService();
  final BluetoothDiscoveryService _btService = BluetoothDiscoveryService();
  final TextEditingController _chatController = TextEditingController();

  final List<TransferRecord> _history = [];
  final List<ChatMessage> _messages = [];
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedHistory();
    _initServices();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _checkUpdates(manual: false);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _networkService.ensureServicesAlive();
    }
  }

  Future<void> _launchQrScannerSafely({bool waitForSheetClose = false}) async {
    if (waitForSheetClose) {
      await Future.delayed(const Duration(milliseconds: 280));
    }
    if (!mounted) return;
    final scannedIp = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (scannedIp != null && scannedIp.isNotEmpty && mounted) {
      _sendFilesToDevice(NetworkDevice(name: 'جهاز QR ($scannedIp)', ip: scannedIp));
    }
  }

  Future<void> _checkUpdates({required bool manual}) async {
    if (_checkingUpdate) return;
    _checkingUpdate = true;

    if (manual && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('جاري التحقق من وجود تحديثات جديدة...'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    final info = await AppUpdateService.checkForUpdate();
    _checkingUpdate = false;
    if (!mounted) return;

    if (info.status == UpdateCheckStatus.updateAvailable) {
      _showUpdateDialog(info);
    } else if (manual) {
      String msg;
      if (info.status == UpdateCheckStatus.upToDate) {
        msg = 'أنت تستخدم أحدث إصدار بالفعل (v${AppUpdateService.currentVersion}) ✅';
      } else if (info.status == UpdateCheckStatus.repoPrivateOrNoRelease) {
        msg = 'تعذر الوصول للتحديثات: تأكد أن مستودع PulseDrop مضبوط على Public وتم نشر Release.';
      } else {
        msg = 'تعذر الاتصال بخادم التحديثات، تأكد من وجود إنترنت.';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _showUpdateDialog(UpdateInfo info) {
    bool isDownloading = false;
    double progress = 0.0;
    String statusText = '';
    String? errorMsg;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.system_update_rounded, color: Color(0xFF0EA5E9)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('تحديث جديد متاح (v${info.latestVersion})'),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'إصدارك الحالي: v${AppUpdateService.currentVersion}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 10),
                  Text(info.releaseNotes, style: const TextStyle(height: 1.4)),
                  if (isDownloading) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: progress > 0 ? progress : null),
                    const SizedBox(height: 8),
                    Text(
                      statusText,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (errorMsg != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorMsg!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                ],
              ),
              actions: [
                if (!isDownloading)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('لاحقاً'),
                  ),
                if (!isDownloading)
                  FilledButton.icon(
                    onPressed: () async {
                      setDialogState(() {
                        isDownloading = true;
                        errorMsg = null;
                        statusText = 'جاري تجهيز التحميل...';
                      });
                      final err = await AppUpdateService.downloadAndInstall(
                        info,
                        onProgress: (pct, rec, total) {
                          final mbRec = (rec / (1024 * 1024)).toStringAsFixed(1);
                          final mbTot = total > 0
                              ? (total / (1024 * 1024)).toStringAsFixed(1)
                              : '?';
                          setDialogState(() {
                            progress = pct;
                            statusText =
                                'جاري التحميل: ${(pct * 100).round()}% ($mbRec / $mbTot MB)';
                          });
                        },
                      );
                      if (err != null) {
                        setDialogState(() {
                          isDownloading = false;
                          errorMsg = err;
                        });
                      } else if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                    },
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('تحديث الآن'),
                  ),
              ],
            );
          },
        );
      },
    );
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
    WidgetsBinding.instance.removeObserver(this);
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

  Widget _buildBluetoothTab(BuildContext sheetCtx) {
    return ValueListenableBuilder<BtUiStatus>(
      valueListenable: _btService.statusNotifier,
      builder: (context, status, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: _btService.isScanningNotifier,
          builder: (context, scanning, _) {
            return ValueListenableBuilder<List<BluetoothDeviceItem>>(
              valueListenable: _btService.devicesNotifier,
              builder: (context, btDevices, _) {
                if (status == BtUiStatus.unsupported) {
                  return const Center(
                    child: Text('هذا الجهاز لا يدعم البلوتوث منخفض الطاقة (BLE).'),
                  );
                }

                if (status == BtUiStatus.bluetoothOff) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bluetooth_disabled_rounded, size: 56, color: Colors.grey),
                          const SizedBox(height: 12),
                          const Text(
                            'البلوتوث مغلق حالياً',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'قم بتشغيل البلوتوث لرصد الموبايلات والأجهزة القريبة بالاسم.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => _btService.turnOnBluetooth(),
                            icon: const Icon(Icons.bluetooth),
                            label: const Text('تشغيل البلوتوث الآن'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (status == BtUiStatus.permissionDenied ||
                    status == BtUiStatus.permissionPermanentlyDenied) {
                  final permPermanent = status == BtUiStatus.permissionPermanentlyDenied;
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline_rounded, size: 54, color: Colors.orange),
                          const SizedBox(height: 12),
                          Text(
                            permPermanent
                                ? 'صلاحية البلوتوث أو الأجهزة القريبة مرفوضة من إعدادات النظام.'
                                : 'يحتاج التطبيق صلاحية الأجهزة القريبة للبحث بالبلوتوث.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () async {
                              if (permPermanent) {
                                await openAppSettings();
                              } else {
                                await _btService.startScan();
                              }
                            },
                            icon: Icon(permPermanent ? Icons.settings : Icons.check_circle_outline),
                            label: Text(permPermanent ? 'فتح إعدادات التطبيق' : 'منح الصلاحيات والبحث'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            scanning
                                ? 'جاري البحث بالبلوتوث...'
                                : 'الأجهزة المقترنة والقريبة (${btDevices.length})',
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
                    if (scanning) const LinearProgressIndicator(),
                    Expanded(
                      child: btDevices.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  scanning
                                      ? 'جاري البحث عن الموبايلات والأجهزة القريبة بالاسم...'
                                      : 'لم يتم العثور على أجهزة مسماة قريبة.\nتأكد من تفعيل البلوتوث والموقع (Location) على الجهازين، أو اقترن بالموبايل الآخر مرة واحدة.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.grey, height: 1.5),
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
                                    leading: CircleAvatar(
                                      backgroundColor: b.isPaired
                                          ? const Color(0xFF059669)
                                          : const Color(0xFF2563EB),
                                      child: Icon(
                                        b.isPaired ? Icons.bluetooth_connected : Icons.bluetooth,
                                        color: Colors.white,
                                      ),
                                    ),
                                    title: Text(
                                      b.name,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(b.signalLabel),
                                    trailing: FilledButton.tonal(
                                      onPressed: () {
                                        Navigator.pop(sheetCtx);
                                        _openWebShareSheet();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'تم اختيار "${b.name}" — امسح QR أو وصّل الهوتسبوت للنقل بأقصى سرعة',
                                            ),
                                          ),
                                        );
                                      },
                                      child: const Text('اتصال سريع'),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _openSendDiscoverySheet() {
    _networkService.startAutoDiscovery();

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
                  TabBar(
                    onTap: (index) {
                      if (index == 1) {
                        _btService.startScan();
                      } else {
                        _networkService.startAutoDiscovery();
                      }
                    },
                    tabs: const [
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
                                                    subtitle: Text('${dev.ip}:${dev.port}'),
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
                        _buildBluetoothTab(ctx),
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
        onRequestQrScanner: () => _launchQrScannerSafely(waitForSheetClose: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  '${_networkService.isVisible ? "الرادار نشط" : "وضع التخفي"} • v${AppUpdateService.currentVersion}',
                  style: TextStyle(
                    fontSize: 11,
                    color: _networkService.isVisible ? Colors.teal : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update_rounded),
            tooltip: 'التحقق من التحديثات',
            onPressed: () => _checkUpdates(manual: true),
          ),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _sendGroupFiles,
                  icon: const Icon(Icons.hub_outlined, size: 17),
                  label: const Text('إرسال جماعي'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _launchQrScannerSafely(waitForSheetClose: false),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 17),
                  label: const Text('مسح QR'),
                ),
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
                  icon: const Icon(Icons.folder_copy_outlined, size: 17),
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
                    ValueListenableBuilder<String?>(
                      valueListenable: _networkService.localIpNotifier,
                      builder: (context, ipVal, _) {
                        return Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            ipVal ?? 'جاري تحديد IP...',
                            style: const TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        );
                      },
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
