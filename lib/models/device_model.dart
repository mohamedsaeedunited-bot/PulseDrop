class NetworkDevice {
  final String name;
  final String ip;
  final int port;
  final String version;

  NetworkDevice({
    required this.name,
    required this.ip,
    this.port = 8080,
    this.version = '4.0',
  });

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

  BluetoothDeviceItem({
    required this.id,
    required this.name,
    required this.rssi,
  });
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
