import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/network_service.dart';

class WebShareSheet extends StatefulWidget {
  final NetworkService networkService;
  final Function(String ip) onQrIpScanned;

  const WebShareSheet({
    super.key,
    required this.networkService,
    required this.onQrIpScanned,
  });

  @override
  State<WebShareSheet> createState() => _WebShareSheetState();
}

class _WebShareSheetState extends State<WebShareSheet> {
  int _selectedTab = 0; // 0: Web Portal, 1: QR Scan, 2: Hotspot QR
  bool _cameraGranted = false;
  bool _checkingCamera = false;
  MobileScannerController? _scannerController;

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    setState(() => _checkingCamera = true);
    final status = await Permission.camera.request();
    if (status.isGranted) {
      _scannerController?.dispose();
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
      setState(() {
        _cameraGranted = true;
        _checkingCamera = false;
      });
    } else {
      setState(() {
        _cameraGranted = false;
        _checkingCamera = false;
      });
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final ip = widget.networkService.localIp ?? 'غير متصل بالواي فاي';
    final webUrl = 'http://$ip:${NetworkService.serverPort}';

    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.78,
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
                ButtonSegment(value: 1, label: Text('مسح QR')),
                ButtonSegment(value: 2, label: Text('هوتسبوت QR')),
              ],
              selected: {_selectedTab},
              onSelectionChanged: (val) {
                final next = val.first;
                setState(() => _selectedTab = next);
                if (next == 1) {
                  _initCamera();
                } else {
                  _scannerController?.stop();
                }
              },
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _selectedTab == 0
                  ? _buildWebPortalTab(webUrl)
                  : _selectedTab == 1
                      ? _buildQrScannerTab()
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
              size: 190,
            ),
          ),
          const SizedBox(height: 14),
          SelectableText(
            webUrl,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0284C7),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'افتح الرابط من متصفح الكمبيوتر أو امسح الكود لتحميل وإرسال الملفات',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _pickWebFiles,
            icon: const Icon(Icons.add_circle_outline),
            label: Text(
              'اختيار ملفات للمشاركة (${widget.networkService.sharedWebFiles.length})',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrScannerTab() {
    if (_checkingCamera) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_cameraGranted || _scannerController == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('يلزم السماح بإذن الكاميرا لمسح رمز QR'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _initCamera,
              child: const Text('تفعيل الكاميرا'),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: MobileScanner(
        controller: _scannerController!,
        errorBuilder: (context, error, child) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 8),
                const Text('تعذر تشغيل الكاميرا، حاول مرة أخرى'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _initCamera,
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          );
        },
        onDetect: (capture) {
          for (final barcode in capture.barcodes) {
            final raw = barcode.rawValue;
            if (raw != null && raw.isNotEmpty) {
              _scannerController?.stop();
              Navigator.pop(context);
              final cleaned = raw
                  .replaceAll('http://', '')
                  .replaceAll('https://', '')
                  .split(':')
                  .first;
              widget.onQrIpScanned(cleaned);
              break;
            }
          }
        },
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
          'النقل بدون راوتر (هوتسبوت)',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'افتح نقطة الاتصال (Hotspot) من موبايلك، ووصّل الموبايل التاني عليها، واضغط "إرسال" وهيكتشفه تلقائياً بدون سحب من الباقة.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'عنوان جهازك الحالي: $webUrl',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
