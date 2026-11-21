import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../models/device_model.dart';

class HistoryScreen extends StatelessWidget {
  final List<TransferRecord> records;

  const HistoryScreen({super.key, required this.records});

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجل النقل')),
      body: SafeArea(
        child: records.isEmpty
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history, size: 64, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('لا توجد عمليات نقل حتى الآن'),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: records.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final rec = records[index];
                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.grey.withOpacity(0.2)),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: rec.isSent
                            ? Colors.blue.withOpacity(0.15)
                            : Colors.green.withOpacity(0.15),
                        child: Icon(
                          rec.isSent ? Icons.upload_rounded : Icons.download_rounded,
                          color: rec.isSent ? Colors.blue : Colors.green,
                        ),
                      ),
                      title: Text(rec.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${rec.isSent ? "إلى" : "من"}: ${rec.peerName} • ${_formatSize(rec.sizeBytes)}',
                      ),
                      trailing: rec.filePath != null
                          ? IconButton(
                              icon: const Icon(Icons.open_in_new),
                              onPressed: () => OpenFilex.open(rec.filePath!),
                            )
                          : null,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
