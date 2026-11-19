import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

class TransferCard extends StatelessWidget {
  final TransferTask task;
  final AppStrings strings;

  const TransferCard({super.key, required this.task, required this.strings});

  @override
  Widget build(BuildContext context) {
    final isSend = task.direction == TransferDirection.send;
    final statusColor = task.status == TransferStatus.completed
        ? AppColors.success
        : task.status == TransferStatus.failed
            ? AppColors.danger
            : AppColors.accent;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isSend ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${task.peerName} • ${formatBytes(task.totalBytes)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.darkSubtext
                              : AppColors.lightSubtext,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      task.status == TransferStatus.inProgress
                          ? task.formattedSpeed
                          : (task.status == TransferStatus.completed
                              ? strings.completed
                              : strings.failed),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: statusColor,
                      ),
                    ),
                    if (task.status == TransferStatus.inProgress)
                      Text(
                        task.etaText,
                        style: const TextStyle(fontSize: 11, color: AppColors.lightSubtext),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: task.status == TransferStatus.completed ? 1.0 : task.progress,
                minHeight: 7,
                backgroundColor: statusColor.withAlpha(35),
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
