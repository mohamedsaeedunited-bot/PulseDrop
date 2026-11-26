import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with WidgetsBindingObserver {
  MobileScannerController? _controller;
  bool _hasPermission = false;
  bool _isPermanentlyDenied = false;
  bool _isLoading = true;
  bool _torchOn = false;
  bool _handledScan = false;
  String? _startError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCameraFlow();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null || !_hasPermission) return;

    if (state == AppLifecycleState.resumed) {
      _startScannerSafely();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      ctrl.stop();
    }
  }

  Future<void> _initCameraFlow() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _startError = null;
      });
    }

    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }

    if (!mounted) return;

    if (!status.isGranted) {
      setState(() {
        _hasPermission = false;
        _isPermanentlyDenied = status.isPermanentlyDenied;
        _isLoading = false;
      });
      return;
    }

    await _controller?.dispose();
    _controller = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      formats: const [BarcodeFormat.qrCode],
    );

    setState(() {
      _hasPermission = true;
      _isPermanentlyDenied = false;
      _isLoading = false;
    });

    // Wait for MobileScanner widget Surface to mount completely before starting CameraX
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _startScannerSafely();
      }
    });
  }

  Future<void> _startScannerSafely() async {
    final ctrl = _controller;
    if (ctrl == null || !mounted || _handledScan) return;
    try {
      await ctrl.start();
      if (mounted && _startError != null) {
        setState(() => _startError = null);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _startError = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res == null || res.files.isEmpty || res.files.first.path == null) {
      return;
    }

    MobileScannerController? tempCtrl;
    try {
      final ctrl = _controller ??
          (tempCtrl = MobileScannerController(autoStart: false));
      final capture = await ctrl.analyzeImage(res.files.first.path!);
      if (capture != null && capture.barcodes.isNotEmpty) {
        final raw = capture.barcodes.first.rawValue;
        if (raw != null && raw.isNotEmpty) {
          _onCodeFound(raw);
          return;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لم يتم العثور على رمز QR واضح في الصورة المختارة'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحليل الصورة: $e')),
        );
      }
    } finally {
      await tempCtrl?.dispose();
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
                try {
                  await _controller!.toggleTorch();
                  if (mounted) setState(() => _torchOn = !_torchOn);
                } catch (_) {}
              },
            ),
            IconButton(
              icon: const Icon(Icons.cameraswitch_outlined),
              tooltip: 'تبديل الكاميرا',
              onPressed: () async {
                try {
                  await _controller!.switchCamera();
                } catch (_) {}
              },
            ),
          ],
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'مسح QR من صورة بالمعرض',
            onPressed: _scanFromGallery,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : !_hasPermission || _controller == null
                ? _buildPermissionDeniedView()
                : _startError != null
                    ? _buildCameraErrorView(_startError!)
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          MobileScanner(
                            controller: _controller!,
                            errorBuilder: (context, error, child) {
                              return _buildCameraErrorView(
                                '${error.errorCode.name} (${error.toString()})',
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
                          IgnorePointer(
                            child: Container(
                              width: 250,
                              height: 250,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFF0EA5E9),
                                  width: 3,
                                ),
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 28,
                            left: 16,
                            right: 16,
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.65),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Text(
                                    'وجّه الكاميرا نحو رمز QR الظاهر على الجهاز الآخر',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.white54),
                                    backgroundColor: Colors.black54,
                                  ),
                                  onPressed: _scanFromGallery,
                                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                                  label: const Text('أو اختر صورة QR من المعرض'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }

  Widget _buildPermissionDeniedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, size: 64, color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              _isPermanentlyDenied
                  ? 'صلاحية الكاميرا مرفوضة بشكل دائم من إعدادات الموبايل.\nافتح الإعدادات وفعّل إذن الكاميرا لتطبيق PulseDrop.'
                  : 'يرجى السماح بصلاحية الكاميرا لمسح رمز QR.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 20),
            if (_isPermanentlyDenied)
              FilledButton.icon(
                onPressed: () async {
                  await openAppSettings();
                  await Future.delayed(const Duration(milliseconds: 500));
                  if (mounted) _initCameraFlow();
                },
                icon: const Icon(Icons.settings),
                label: const Text('فتح إعدادات الصلاحيات'),
              )
            else
              FilledButton.icon(
                onPressed: _initCameraFlow,
                icon: const Icon(Icons.camera_alt),
                label: const Text('السماح بتشغيل الكاميرا'),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              onPressed: _scanFromGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('مسح صورة QR من المعرض'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraErrorView(String details) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded, color: Colors.orangeAccent, size: 58),
            const SizedBox(height: 14),
            const Text(
              'تعذر تشغيل عدسة الكاميرا حالياً',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                details,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _initCameraFlow,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  onPressed: _scanFromGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('مسح من المعرض'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
