import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  MobileScannerController? _controller;
  bool _hasPermission = false;
  bool _isLoading = true;
  bool _torchOn = false;
  bool _handledScan = false;

  @override
  void initState() {
    super.initState();
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    setState(() => _isLoading = true);
    final status = await Permission.camera.request();
    if (status.isGranted) {
      await _controller?.dispose();
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
      );
      if (mounted) {
        setState(() {
          _hasPermission = true;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _hasPermission = false;
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onCodeFound(String raw) {
    if (_handledScan) return;
    _handledScan = true;
    _controller?.stop();
    final cleanedIp = raw
        .trim()
        .replaceAll('http://', '')
        .replaceAll('https://', '')
        .split(':')
        .first
        .split('/')
        .first;
    Navigator.pop(context, cleanedIp);
  }

  Future<void> _scanFromGallery() async {
    if (_controller == null) return;
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res != null && res.files.isNotEmpty && res.files.first.path != null) {
      final capture = await _controller!.analyzeImage(res.files.first.path!);
      if (capture != null && capture.barcodes.isNotEmpty) {
        final raw = capture.barcodes.first.rawValue;
        if (raw != null && raw.isNotEmpty) {
          _onCodeFound(raw);
          return;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يتم العثور على رمز QR في الصورة المختارة')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('مسح رمز QR للاتصال'),
        actions: [
          if (_hasPermission && _controller != null) ...[
            IconButton(
              icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
              tooltip: 'الفلاش',
              onPressed: () async {
                await _controller!.toggleTorch();
                setState(() => _torchOn = !_torchOn);
              },
            ),
            IconButton(
              icon: const Icon(Icons.photo_library_outlined),
              tooltip: 'اختيار صورة QR من المعرض',
              onPressed: _scanFromGallery,
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : !_hasPermission || _controller == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.no_photography, size: 64, color: Colors.white70),
                          const SizedBox(height: 16),
                          const Text(
                            'يرجى السماح بصلاحية الكاميرا لمسح رمز QR',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _setupCamera,
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('تفعيل الكاميرا'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      MobileScanner(
                        controller: _controller!,
                        errorBuilder: (context, error, child) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 54),
                                  const SizedBox(height: 12),
                                  Text(
                                    'تعذر تشغيل الكاميرا (${error.errorCode.name})',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white, fontSize: 15),
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: _setupCamera,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('إعادة المحاولة'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        onDetect: (capture) {
                          for (final barcode in capture.barcodes) {
                            final raw = barcode.rawValue;
                            if (raw != null && raw.isNotEmpty) {
                              _onCodeFound(raw);
                              break;
                            }
                          }
                        },
                      ),
                      Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF0EA5E9), width: 3),
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      const Positioned(
                        bottom: 36,
                        child: Text(
                          'وجّه الكاميرا نحو رمز QR الظاهر على الجهاز الآخر',
                          style: TextStyle(
                            color: Colors.white,
                            backgroundColor: Colors.black54,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
