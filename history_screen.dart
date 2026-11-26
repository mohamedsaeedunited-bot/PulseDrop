import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../models/device_model.dart';

class HistoryScreen extends StatefulWidget {
  final List<TransferRecord> records;
  final VoidCallback? onClearHistory;

  const HistoryScreen({
    super.key,
    required this.records,
    this.onClearHistory,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _filterIndex = 0;

  String _formatSize(int bytes) {
    if (bytes <= 0) return 'غير معروف';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDateTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'م' : 'ص';
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year} • $hour:$min $period';
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) {
      return Icons.image_rounded;
    }
    if (['mp4', 'mkv', 'avi', 'mov', 'webm'].contains(ext)) {
      return Icons.videocam_rounded;
    }
    if (['mp3', 'wav', 'aac', 'm4a', 'ogg'].contains(ext)) {
      return Icons.audiotrack_rounded;
    }
    if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'].contains(ext)) {
      return Icons.description_rounded;
    }
    if (['apk'].contains(ext)) {
      return Icons.android_rounded;
    }
    if (['zip', 'rar', '7z'].contains(ext)) {
      return Icons.folder_zip_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  Color _getFileColor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return Colors.purple;
    if (['mp4', 'mkv', 'avi', 'mov'].contains(ext)) return Colors.deepOrange;
    if (['mp3', 'wav', 'aac', 'm4a'].contains(ext)) return Colors.pink;
    if (['pdf', 'doc', 'docx', 'txt'].contains(ext)) return Colors.blue;
    if (['apk'].contains(ext)) return Colors.green;
    return const Color(0xFF0284C7);
  }

  bool _isImage(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }

  bool _isText(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['txt', 'json', 'csv', 'log', 'xml', 'md', 'html', 'dart'].contains(ext);
  }

  Future<void> _previewRecord(TransferRecord rec) async {
    if (rec.filePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مسار الملف غير متوفر')),
      );
      return;
    }
    final file = File(rec.filePath!);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الملف لم يعد موجوداً في هذا المسار')),
        );
      }
      return;
    }

    if (_isImage(rec.fileName) && mounted) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                title: Text(rec.fileName, style: const TextStyle(fontSize: 15)),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () {
                      Navigator.pop(ctx);
                      OpenFilex.open(rec.filePath!);
                    },
                  ),
                ],
              ),
              Flexible(
                child: InteractiveViewer(
                  child: Image.file(file, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
      return;
    }

    if (_isText(rec.fileName) && mounted) {
      final content = await file.readAsString();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(rec.fileName),
          content: SizedBox(
            width: double.maxFinite,
            height: 320,
            child: SingleChildScrollView(
              child: SelectableText(content),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                OpenFilex.open(rec.filePath!);
              },
              child: const Text('فتح في تطبيق خارجي'),
            ),
          ],
        ),
      );
      return;
    }

    await OpenFilex.open(rec.filePath!);
  }

  Future<void> _openInPhone(TransferRecord rec) async {
    if (rec.filePath == null) return;
    final file = File(rec.filePath!);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الملف غير موجود على الموبايل')),
        );
      }
      return;
    }
    await OpenFilex.open(rec.filePath!);
  }

  @override
  Widget build(BuildContext context) {
    final sentCount = widget.records.where((r) => r.isSent).length;
    final receivedCount = widget.records.where((r) => !r.isSent).length;

    final filtered = _filterIndex == 0
        ? widget.records
        : _filterIndex == 1
            ? widget.records.where((r) => r.isSent).toList()
            : widget.records.where((r) => !r.isSent).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل الملفات المرسلة والمستلمة'),
        actions: [
          if (widget.records.isNotEmpty && widget.onClearHistory != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'مسح السجل',
              onPressed: () {
                widget.onClearHistory!();
                setState(() {});
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text('الكل (${widget.records.length})'),
                    selected: _filterIndex == 0,
                    onSelected: (_) => setState(() => _filterIndex = 0),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('المرسلة ($sentCount)'),
                    selected: _filterIndex == 1,
                    onSelected: (_) => setState(() => _filterIndex = 1),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('المستلمة ($receivedCount)'),
                    selected: _filterIndex == 2,
                    onSelected: (_) => setState(() => _filterIndex = 2),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.folder_open_rounded, size: 68, color: Colors.grey),
                          SizedBox(height: 12),
                          Text(
                            'لا توجد ملفات في هذه القائمة حالياً',
                            style: TextStyle(fontSize: 15, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final rec = filtered[index];
                        final fileColor = _getFileColor(rec.fileName);

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.grey.withOpacity(0.18),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(11),
                                    decoration: BoxDecoration(
                                      color: fileColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      _getFileIcon(rec.fileName),
                                      color: fileColor,
                                      size: 26,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          rec.fileName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: rec.isSent
                                                    ? Colors.blue.withOpacity(0.12)
                                                    : Colors.green.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                rec.isSent
                                                    ? 'مُرسل إلى ${rec.peerName}'
                                                    : 'مُستلم من ${rec.peerName}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: rec.isSent
                                                      ? Colors.blue.shade700
                                                      : Colors.green.shade700,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Directionality(
                                              textDirection: TextDirection.ltr,
                                              child: Text(
                                                _formatSize(rec.sizeBytes),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          _formatDateTime(rec.timestamp),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (rec.filePath != null) ...[
                                const Divider(height: 20),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _previewRecord(rec),
                                        icon: const Icon(Icons.visibility_outlined, size: 18),
                                        label: const Text('معاينة'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () => _openInPhone(rec),
                                        icon: const Icon(Icons.folder_open_rounded, size: 18),
                                        label: const Text('فتح في الموبايل'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
