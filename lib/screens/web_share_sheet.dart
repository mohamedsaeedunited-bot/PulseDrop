import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../services/transfer_engine.dart';
import '../theme/app_theme.dart';

class WebShareSheet extends StatefulWidget {
  final String? localIp;
  final TransferEngine engine;
  final AppStrings strings;
  final ValueChanged<String> onScannedIp;

  const WebShareSheet({
    super.key,
    required this.localIp,
    required this.engine,
    required this.strings,
    required this.onScannedIp,
  });

  @override
  State<WebShareSheet> createState() => _WebShareSheetState();
}

class _WebShareSheetState extends State<WebShareSheet> {
  int _tab = 0;
  bool _handledScan = false;
  final TextEditingController _ssidCtrl = TextEditingController(text: 'PulseDrop_Hotspot');
  final TextEditingController _passCtrl = TextEditingController(text: '12345678');

  String get _webUrl =>
      widget.localIp != null ? 'http://${widget.localIp}:${TransferEngine.serverPort}' : '';

  String get _wifiQrData => 'WIFI:T:WPA;S:${_ssidCtrl.text};P:${_passCtrl.text};;';

  Future<void> _pickFilesForWeb() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    final items = <SharedFileItem>[];
    for (final f in result.files) {
      if (f.path != null) {
        items.add(SharedFileItem(
          id: '${DateTime.now().microsecondsSinceEpoch}_${items.length}',
          name: f.name,
          path: f.path!,
          size: f.size,
        ));
      }
    }
    widget.engine.addWebSharedFiles(items);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      minChildSize: 0.55,
      expand: false,
      builder: (_, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.withAlpha(90),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 14),
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 0, label: Text(s.showQrTab)),
                  ButtonSegment(value: 1, label: Text(s.scanQrTab)),
                  ButtonSegment(value: 2, label: Text(s.hotspotTab)),
                ],
                selected: {_tab},
                onSelectionChanged: (val) => setState(() {
                  _tab = val.first;
                  _handledScan = false;
                }),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _tab == 0
                    ? _buildMyQrView(scrollController, s)
                    : _tab == 1
                        ? _buildScannerView()
                        : _buildHotspotQrView(scrollController, s),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMyQrView(ScrollController controller, AppStrings s) {
    return ListView(
      controller: controller,
      children: [
        Text(
          s.webShareTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          s.webShareDesc,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.lightSubtext),
        ),
        const SizedBox(height: 16),
        if (widget.engine.pinEnabled)
          Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warning.withAlpha(30),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'PIN: ${widget.engine.webPin}',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.warning),
              ),
            ),
          ),
        if (_webUrl.isNotEmpty) ...[
          Center(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: QrImageView(
                data: _webUrl,
                version: QrVersions.auto,
                size: 200,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: AppColors.primary),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.circle,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _webUrl));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.copied)));
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_webUrl, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
                    const SizedBox(width: 8),
                    const Icon(Icons.copy_rounded, size: 16, color: AppColors.primary),
                  ],
                ),
              ),
            ),
          ),
        ] else
          Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(s.connectSameWifi))),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          onPressed: _pickFilesForWeb,
          icon: const Icon(Icons.add_circle_outline_rounded),
          label: Text(s.addFilesForWeb),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        if (widget.engine.webSharedFiles.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${s.sharedFilesCount} ${widget.engine.webSharedFiles.length}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              TextButton(
                onPressed: () {
                  widget.engine.clearWebSharedFiles();
                  setState(() {});
                },
                child: Text(s.clearList),
              ),
            ],
          ),
          ...widget.engine.webSharedFiles.map(
            (f) => ListTile(
              dense: true,
              leading: Icon(
                f.isVideo ? Icons.play_circle_fill_rounded : Icons.insert_drive_file_rounded,
                color: AppColors.accent,
              ),
              title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(formatBytes(f.size)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHotspotQrView(ScrollController controller, AppStrings s) {
    return ListView(
      controller: controller,
      children: [
        Text(s.hotspotHint, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 14),
        TextField(
          controller: _ssidCtrl,
          decoration: InputDecoration(labelText: s.hotspotName, border: const OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passCtrl,
          decoration: InputDecoration(labelText: s.hotspotPass, border: const OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: QrImageView(
              data: _wifiQrData,
              version: QrVersions.auto,
              size: 200,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: AppColors.accent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScannerView() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: MobileScanner(
        onDetect: (BarcodeCapture capture) {
          if (_handledScan) return;
          for (final barcode in capture.barcodes) {
            final raw = barcode.rawValue;
            if (raw != null && raw.startsWith('http://')) {
              final uri = Uri.tryParse(raw);
              if (uri != null && uri.host.isNotEmpty) {
                _handledScan = true;
                Navigator.pop(context);
                widget.onScannedIp(uri.host);
                break;
              }
            }
          }
        },
      ),
    );
  }
}
