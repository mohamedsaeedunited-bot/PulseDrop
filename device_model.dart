class NetworkDevice {
  final String name;
  final String ip;
  final int port;
  final String version;
  final DateTime lastSeen;

  NetworkDevice({
    required this.name,
    required this.ip,
    this.port = 8080,
    this.version = '5.3',
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkDevice && runtimeType == other.runtimeType && ip == other.ip;

  @override
  int get hashCode => ip.hashCode;
}

class BluetoothDeviceItem {
  final String id;
  final String name;
  final int rssi;
  final bool isPaired;

  BluetoothDeviceItem({
    required this.id,
    required this.name,
    required this.rssi,
    this.isPaired = false,
  });

  String get signalLabel {
    if (isPaired && rssi == 0) return 'جهاز مقترن مسبقاً';
    if (rssi >= -60) return isPaired ? 'مقترن • قريب جداً' : 'قريب جداً • إشارة ممتازة';
    if (rssi >= -75) return isPaired ? 'مقترن • قريب' : 'قريب • إشارة جيدة';
    return isPaired ? 'مقترن • متوسط المسافة' : 'متوسط المسافة';
  }
}

class TransferProgress {
  final String fileName;
  final String? filePath;
  final String peerName;
  final bool isSending;
  final int bytesTransferred;
  final int totalBytes;
  final double speedBytesPerSec;
  final int remainingSeconds;
  final bool isCompleted;
  final bool isFailed;
  final String? errorMessage;

  TransferProgress({
    required this.fileName,
    this.filePath,
    required this.peerName,
    required this.isSending,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.speedBytesPerSec,
    required this.remainingSeconds,
    this.isCompleted = false,
    this.isFailed = false,
    this.errorMessage,
  });

  double get progress {
    if (isCompleted) return 1.0;
    if (totalBytes <= 0) return 0.0;
    return (bytesTransferred / totalBytes).clamp(0.0, 1.0);
  }

  int get percentage => (progress * 100).round();
}

class TransferRecord {
  final String fileName;
  final String? filePath;
  final String peerName;
  final bool isSent;
  final DateTime timestamp;
  final int sizeBytes;

  TransferRecord({
    required this.fileName,
    this.filePath,
    required this.peerName,
    required this.isSent,
    required this.timestamp,
    this.sizeBytes = 0,
  });

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'filePath': filePath,
        'peerName': peerName,
        'isSent': isSent,
        'timestamp': timestamp.toIso8601String(),
        'sizeBytes': sizeBytes,
      };

  factory TransferRecord.fromJson(Map<String, dynamic> json) => TransferRecord(
        fileName: json['fileName'] ?? 'ملف',
        filePath: json['filePath'],
        peerName: json['peerName'] ?? 'جهاز قريب',
        isSent: json['isSent'] ?? true,
        timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
        sizeBytes: json['sizeBytes'] ?? 0,
      );
}

class ChatMessage {
  final String sender;
  final String text;
  final DateTime timestamp;
  final bool isMe;

  ChatMessage({
    required this.sender,
    required this.text,
    required this.timestamp,
    required this.isMe,
  });
}
