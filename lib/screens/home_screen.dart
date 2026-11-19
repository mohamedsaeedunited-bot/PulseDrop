import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../services/discovery_service.dart';
import '../services/transfer_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/floating_dock.dart';
import '../widgets/radar_widget.dart';
import '../widgets/transfer_card.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'web_share_sheet.dart';

class HomeScreen extends StatefulWidget {
  final bool isDark;
  final bool isArabic;
  final VoidCallback onToggleTheme;
  final VoidCallback onToggleLanguage;

  const HomeScreen({
    super.key,
    required this.isDark,
    required this.isArabic,
    required this.onToggleTheme,
    required this.onToggleLanguage,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final DiscoveryService _discovery;
  late final TransferEngine _engine;
  final TextEditingController _chatController = TextEditingController();
  bool _ready = false;
  bool _multiDrop = false;
  final Set<String> _selectedPeerIds = {};

  AppStrings get s => AppStrings(widget.isArabic);

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    await _requestPermissions();
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('device_name') ?? 'PulseDrop Phone';
    final savedId = prefs.getString('device_id') ??
        'pd_${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString('device_id', savedId);

    _discovery = DiscoveryService(deviceId: savedId, deviceName: savedName);
    _engine = TransferEngine();

    await _engine.init(savedName);
    await _discovery.start();

    if (mounted) setState(() => _ready = true);
  }

  Future<void> _requestPermissions() async {
    try {
      await [
        Permission.storage,
        Permission.photos,
        Permission.videos,
        Permission.audio,
        Permission.camera,
      ].request();
    } catch (_) {}
  }

  Future<void> _pickAndSendToPeers(List<PeerDevice> targets) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    for (final peer in targets) {
      for (final pf in result.files) {
        if (pf.path != null) {
          await _engine.sendFileToPeer(
            ip: peer.ip,
            port: peer.port,
            peerName: peer.name,
            file: File(pf.path!),
            fileName: pf.name,
          );
        }
      }
    }
    setState(() {
      _selectedPeerIds.clear();
      _multiDrop = false;
    });
  }

  Future<void> _sendQuickChat() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    if (_discovery.peers.isEmpty) {
      _showManualIpDialog(chatText: text);
      return;
    }

    for (final peer in _discovery.peers) {
      await _engine.sendChatToPeer(ip: peer.ip, port: peer.port, text: text);
    }
    _chatController.clear();
  }

  void _onPeerTap(PeerDevice peer) {
    if (_multiDrop) {
      setState(() {
        if (_selectedPeerIds.contains(peer.id)) {
          _selectedPeerIds.remove(peer.id);
        } else {
          _selectedPeerIds.add(peer.id);
        }
      });
    } else {
      _pickAndSendToPeers([peer]);
    }
  }

  void _onSendDockTap() {
    if (_multiDrop && _selectedPeerIds.isNotEmpty) {
      final targets = _discovery.peers.where((p) => _selectedPeerIds.contains(p.id)).toList();
      _pickAndSendToPeers(targets);
      return;
    }
    if (_discovery.peers.isNotEmpty) {
      _showPeerPickerDialog();
    } else {
      _showManualIpDialog();
    }
  }

  void _showPeerPickerDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.pickTargetDevice, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            ..._discovery.peers.map(
              (peer) => ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.smartphone_rounded, color: Colors.white),
                ),
                title: Text(peer.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(peer.ip),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSendToPeers([peer]);
                },
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.lan_rounded, color: AppColors.accent),
              title: Text(s.enterIpManually),
              onTap: () {
                Navigator.pop(context);
                _showManualIpDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showManualIpDialog({String? prefillIp, String? chatText}) {
    final ipCtrl = TextEditingController(text: prefillIp ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.enterIpManually),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_discovery.peers.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(s.noDevicesFound, style: const TextStyle(fontSize: 12)),
              ),
            TextField(
              controller: ipCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: '192.168.1.5',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
          FilledButton(
            onPressed: () async {
              final ip = ipCtrl.text.trim();
              if (ip.isEmpty) return;
              Navigator.pop(context);
              final fakePeer = PeerDevice(
                id: ip,
                name: ip,
                ip: ip,
                port: TransferEngine.serverPort,
                lastSeen: DateTime.now(),
              );
              if (chatText != null) {
                await _engine.sendChatToPeer(ip: ip, port: TransferEngine.serverPort, text: chatText);
                _chatController.clear();
              } else {
                await _pickAndSendToPeers([fakePeer]);
              }
            },
            child: Text(s.connectAndSend),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog() {
    final ctrl = TextEditingController(text: _discovery.deviceName);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.renameDevice),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(labelText: s.deviceName, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
          FilledButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('device_name', name);
                _discovery.updateDeviceName(name);
                _engine.deviceName = name;
              }
              if (mounted) Navigator.pop(context);
            },
            child: Text(s.save),
          ),
        ],
      ),
    );
  }

  void _openWebShareSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => WebShareSheet(
        localIp: _discovery.localIp,
        engine: _engine,
        strings: s,
        onScannedIp: (ip) => _showManualIpDialog(prefillIp: ip),
      ),
    );
  }

  @override
  void dispose() {
    _chatController.dispose();
    if (_ready) {
      _discovery.dispose();
      _engine.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset('assets/icon/pulsedrop_icon.png', width: 34, height: 34),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.appName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                Text(
                  _discovery.stealthMode
                      ? s.stealthOn
                      : (_discovery.localIp != null ? s.serverRunning : s.offline),
                  style: TextStyle(
                    fontSize: 11,
                    color: _discovery.stealthMode
                        ? AppColors.warning
                        : (_discovery.localIp != null ? AppColors.success : AppColors.danger),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_discovery.stealthMode ? Icons.visibility_off_rounded : Icons.visibility_rounded),
            onPressed: () => _discovery.toggleStealth(),
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    engine: _engine,
                    strings: s,
                    isDark: widget.isDark,
                    onToggleTheme: widget.onToggleTheme,
                    onToggleLanguage: widget.onToggleLanguage,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([_discovery, _engine]),
        builder: (context, _) {
          return Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 115),
                children: [
                  // Quick Local Chat Bar
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.chat_rounded, color: AppColors.accent, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _chatController,
                              decoration: InputDecoration(
                                hintText: s.quickChatHint,
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onSubmitted: (_) => _sendQuickChat(),
                            ),
                          ),
                          IconButton(
                            onPressed: _sendQuickChat,
                            icon: const Icon(Icons.send_rounded, color: AppColors.primary, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_engine.chatMessages.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_engine.chatMessages.first.sender}: ${_engine.chatMessages.first.text}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _engine.chatMessages.first.text));
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.copied)));
                            },
                            child: Text(s.copy),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 10),

                  // Multi-Drop toggle bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilterChip(
                        label: Text(s.multiDropMode),
                        selected: _multiDrop,
                        avatar: const Icon(Icons.hub_rounded, size: 16),
                        onSelected: (v) => setState(() {
                          _multiDrop = v;
                          if (!v) _selectedPeerIds.clear();
                        }),
                      ),
                      if (_multiDrop && _selectedPeerIds.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: _onSendDockTap,
                          icon: const Icon(Icons.send_rounded, size: 16),
                          label: Text('${s.sendToSelected} (${_selectedPeerIds.length})'),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 8),

                  Center(
                    child: RadarWidget(
                      deviceName: _discovery.deviceName,
                      localIp: _discovery.localIp,
                      stealthMode: _discovery.stealthMode,
                      peers: _discovery.peers,
                      selectedPeerIds: _selectedPeerIds,
                      onCenterTap: _showRenameDialog,
                      onPeerTap: _onPeerTap,
                    ),
                  ),

                  const SizedBox(height: 8),
                  Text(
                    _discovery.peers.isEmpty ? s.scanningRadar : s.tapDeviceToSend,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.connectSameWifi,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: AppColors.lightSubtext),
                  ),

                  if (_engine.activeTasks.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(s.activeTransfers, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 10),
                    ..._engine.activeTasks.map((t) => TransferCard(task: t, strings: s)),
                  ],
                ],
              ),

              Align(
                alignment: Alignment.bottomCenter,
                child: FloatingDock(
                  strings: s,
                  onSendTap: _onSendDockTap,
                  onQrTap: _openWebShareSheet,
                  onHistoryTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HistoryScreen(engine: _engine, strings: s),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
