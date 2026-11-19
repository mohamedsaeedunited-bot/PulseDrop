class PeerDevice {
  final String id;
  final String name;
  final String ip;
  final int port;
  final DateTime lastSeen;

  PeerDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.lastSeen,
  });

  String get baseUrl => 'http://$ip:$port';
}

enum TransferDirection { send, receive }
enum TransferStatus { inProgress, completed, failed }

class TransferTask {
  final String id;
  final String fileName;
  final String filePath;
  final int totalBytes;
  int transferredBytes;
  double speedBytesPerSec;
  final TransferDirection direction;
  TransferStatus status;
  final DateTime timestamp;
  final String peerName;

  TransferTask({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.totalBytes,
    this.transferredBytes = 0,
    this.speedBytesPerSec = 0,
    required this.direction,
    this.status = TransferStatus.inProgress,
    required this.timestamp,
    required this.peerName,
  });

  double get progress {
    if (totalBytes <= 0) return 0;
    return (transferredBytes / totalBytes).clamp(0.0, 1.0);
  }

  String get category {
    final ext = fileName.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic'].contains(ext)) return 'images';
    if (['mp4', 'mkv', 'mov', 'avi', 'webm'].contains(ext)) return 'videos';
    if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'ppt', 'pptx'].contains(ext)) return 'docs';
    if (['apk', 'xapk'].contains(ext)) return 'apps';
    return 'other';
  }

  String get formattedSpeed {
    final mb = speedBytesPerSec / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB/s';
    final kb = speedBytesPerSec / 1024;
    return '${kb.toStringAsFixed(0)} KB/s';
  }

  String get etaText {
    if (speedBytesPerSec <= 0 || totalBytes <= transferredBytes) return '--';
    final remainingSec = ((totalBytes - transferredBytes) / speedBytesPerSec).ceil();
    if (remainingSec < 60) return '${remainingSec}s';
    final min = remainingSec ~/ 60;
    final sec = remainingSec % 60;
    return '${min}m ${sec}s';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'filePath': filePath,
        'totalBytes': totalBytes,
        'transferredBytes': transferredBytes,
        'direction': direction.name,
        'status': status.name,
        'timestamp': timestamp.toIso8601String(),
        'peerName': peerName,
      };

  factory TransferTask.fromJson(Map<String, dynamic> json) => TransferTask(
        id: json['id'] ?? '',
        fileName: json['fileName'] ?? 'file',
        filePath: json['filePath'] ?? '',
        totalBytes: json['totalBytes'] ?? 0,
        transferredBytes: json['transferredBytes'] ?? 0,
        direction: json['direction'] == 'send'
            ? TransferDirection.send
            : TransferDirection.receive,
        status: json['status'] == 'completed'
            ? TransferStatus.completed
            : TransferStatus.failed,
        timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
        peerName: json['peerName'] ?? 'Device',
      );
}

class SharedFileItem {
  final String id;
  final String name;
  final String path;
  final int size;

  SharedFileItem({
    required this.id,
    required this.name,
    required this.path,
    required this.size,
  });

  bool get isVideo {
    final ext = name.split('.').last.toLowerCase();
    return ['mp4', 'webm', 'mov', 'mkv'].contains(ext);
  }
}

class ChatMessage {
  final String text;
  final String sender;
  final bool isMe;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.sender,
    required this.isMe,
    required this.timestamp,
  });
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
