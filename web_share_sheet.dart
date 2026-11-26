import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/network_service.dart';

class WebShareSheet extends StatefulWidget {
  final NetworkService networkService;
  final VoidCallback onRequestQrScanner;

  const WebShareSheet({
    super.key,
    required this.networkService,
    required this.onRequestQrScanner,
  });

  @override
  State<WebShareSheet> createState() => _WebShareSheetState();
}

class _WebShareSheetState extends State<WebShareSheet> {
  int _selectedTab = 0;

  Future<void> _pickWebFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      setState(() {
        for (final f in result.files) {
          if (f.path != null) {
            widget.networkService.sharedWebFiles.add(File(f.path!));
          }
        }
      });
    }
  }

  void _closeAndLaunchCamera() {
    Navigator.pop(context);
    widget.onRequestQrScanner();
  }

  @override
  Widget build(BuildContext context) {
    final ip = widget.networkService.localIp ?? 'غير متصل بالواي فاي';
    final webUrl = 'http://$ip:${widget.networkService.activePort}';

    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.74,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('بوابة الويب')),
                ButtonSegment(value: 1, label: Text('مسح QR بالكاميرا')),
                ButtonSegment(value: 2, label: Text('هوتسبوت')),
              ],
              selected: {_selectedTab},
              onSelectionChanged: (val) {
                final next = val.first;
                if (next == 1) {
                  _closeAndLaunchCamera();
                } else {
                  setState(() => _selectedTab = next);
                }
              },
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _selectedTab == 0
                  ? _buildWebPortalTab(webUrl)
                  : _buildHotspotTab(webUrl),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebPortalTab(String webUrl) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: QrImageView(
              data: webUrl,
              size: 185,
            ),
          ),
          const SizedBox(height: 14),
          Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(
              webUrl,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0284C7),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'افتح الرابط من متصفح الكمبيوتر أو امسح الكود لتحميل وإرسال الملفات',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _pickWebFiles,
                icon: const Icon(Icons.add_circle_outline),
                label: Text(
                  'مشاركة ملفات (${widget.networkService.sharedWebFiles.length})',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _closeAndLaunchCamera,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('فتح كاميرا المسح'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHotspotTab(String webUrl) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.wifi_tethering, size: 64, color: Color(0xFF0284C7)),
        const SizedBox(height: 16),
        const Text(
          'النقل السريع بدون راوتر (هوتسبوت)',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '1. افتح نقطة الاتصال (Hotspot) من موبايلك.\n2. وصّل الموبايل الآخر عليها.\n3. اضغط "إرسال" وسيظهر الموبايل تلقائياً وتبعت وتستلم في الاتجاهين بسرعة فائقة.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, height: 1.5),
          ),
        ),
        const SizedBox(height: 16),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            webUrl,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
