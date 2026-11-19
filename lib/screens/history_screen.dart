import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../services/transfer_engine.dart';
import '../theme/app_theme.dart';

class HistoryScreen extends StatefulWidget {
  final TransferEngine engine;
  final AppStrings strings;

  const HistoryScreen({super.key, required this.engine, required this.strings});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.history, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (widget.engine.history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: s.clearHistory,
              onPressed: () => widget.engine.clearHistory(),
            ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _chip('all', s.allTab),
                _chip('images', s.imagesTab),
                _chip('videos', s.videosTab),
                _chip('docs', s.docsTab),
                _chip('apps', s.appsTab),
              ],
            ),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: widget.engine,
              builder: (context, _) {
                final filtered = _filter == 'all'
                    ? widget.engine.history
                    : widget.engine.history.where((e) => e.category == _filter).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_open_rounded, size: 64, color: AppColors.lightSubtext.withAlpha(120)),
                        const SizedBox(height: 12),
                        Text(s.noHistory, style: const TextStyle(color: AppColors.lightSubtext)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final isSend = item.direction == TransferDirection.send;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: (isSend ? AppColors.primary : AppColors.accent).withAlpha(28),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isSend ? Icons.north_east_rounded : Icons.south_west_rounded,
                            color: isSend ? AppColors.primary : AppColors.accent,
                          ),
                        ),
                        title: Text(
                          item.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        subtitle: Text(
                          '${isSend ? s.sent : s.received} • ${formatBytes(item.totalBytes)} • ${item.peerName}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: TextButton(
                          onPressed: () => OpenFilex.open(item.filePath),
                          child: Text(s.openFile),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String key, String label) {
    final active = _filter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: active,
        onSelected: (_) => setState(() => _filter = key),
      ),
    );
  }
}
