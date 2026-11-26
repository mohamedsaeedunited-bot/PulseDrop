import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../models/device_model.dart';

class TransferProgressCard extends StatelessWidget {
  final TransferProgress transfer;
  final VoidCallback onDismiss;
  final VoidCallback? onPreview;

  const TransferProgressCard({
    super.key,
    required this.transfer,
    required this.onDismiss,
    this.onPreview,
  });

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '';
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(0)} KB/s';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String _formatEta(int seconds) {
    if (seconds <= 1) return 'ثوانٍ معدودة...';
    if (seconds < 60) return 'متبقي $seconds ثانية';
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return 'متبقي $mins د و $secs ث';
  }

  @override
  Widget build(BuildContext context) {
    final bool done = transfer.isCompleted;
    final bool failed = transfer.isFailed;

    final List<Color> gradientColors = done
        ? [const Color(0xFF059669), const Color(0xFF10B981)]
        : failed
            ? [const Color(0xFFDC2626), const Color(0xFFEF4444)]
            : [const Color(0xFF0284C7), const Color(0xFF4F46E5)];

    final String statusTitle = done
        ? (transfer.isSending ? 'تم الإرسال بنجاح ✅' : 'تم الاستلام بنجاح ✅')
        : failed
            ? 'تعذر إكمال النقل ❌'
            : (transfer.isSending
                ? 'جاري الإرسال إلى ${transfer.peerName}'
                : 'جاري الاستلام من ${transfer.peerName}');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  done
                      ? Icons.check_circle_rounded
                      : failed
                          ? Icons.error_rounded
                          : (transfer.isSending
                              ? Icons.rocket_launch_rounded
                              : Icons.downloading_rounded),
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      transfer.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${transfer.percentage}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              if (done || failed) ...[
                const SizedBox(width: 6),
                IconButton(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: transfer.progress,
              minHeight: 9,
              backgroundColor: Colors.white.withOpacity(0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_formatBytes(transfer.bytesTransferred)} / ${_formatBytes(transfer.totalBytes)}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.92),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!done && !failed)
                Row(
                  children: [
                    if (transfer.speedBytesPerSec > 0) ...[
                      Text(
                        _formatSpeed(transfer.speedBytesPerSec),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _formatEta(transfer.remainingSeconds),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                )
              else if (done && transfer.filePath != null)
                Row(
                  children: [
                    if (onPreview != null)
                      TextButton.icon(
                        onPressed: onPreview,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white.withOpacity(0.2),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.visibility, size: 15),
                        label: const Text('معاينة', style: TextStyle(fontSize: 12)),
                      ),
                    const SizedBox(width: 6),
                    TextButton.icon(
                      onPressed: () => OpenFilex.open(transfer.filePath!),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF065F46),
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 15),
                      label: const Text(
                        'فتح الملف',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
