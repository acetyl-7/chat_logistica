import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String text;
  final String senderId;
  final String senderName;
  final String senderPlate;
  final String sender; // Explicit role
  final String? imageUrl;
  final String? fileUrl;
  final String? fileName;
  final String type; // 'text', 'image', 'document'
  final String? driverId;
  final double? latitude;
  final double? longitude;
  final bool isPending;
  final String status;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.senderName,
    required this.senderPlate,
    this.sender = 'driver', // Always 'driver' from the mobile app
    this.imageUrl,
    this.fileUrl,
    this.fileName,
    this.type = 'text',
    this.driverId,
    this.latitude,
    this.longitude,
    this.isPending = false,
    this.status = 'sent',
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'senderId': senderId,
      'senderName': senderName,
      'senderPlate': senderPlate,
      'sender': sender, // Essential for HQ filtering
      'type': type,
      if (driverId != null) 'driverId': driverId,
      if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
      if (fileUrl != null && fileUrl!.isNotEmpty) 'fileUrl': fileUrl,
      if (fileName != null && fileName!.isNotEmpty) 'fileName': fileName,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'status': status,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  factory ChatMessage.fromMap(
    String id,
    Map<String, dynamic> map, {
    bool isPending = false,
  }) {
    final timestampValue = map['timestamp'];

    DateTime dateTime;
    if (timestampValue is Timestamp) {
      dateTime = timestampValue.toDate();
    } else if (timestampValue is DateTime) {
      dateTime = timestampValue;
    } else {
      dateTime = DateTime.now();
    }

    final imageUrl = map['imageUrl'] as String?;
    final fileUrl = map['fileUrl'] as String?;
    // Para compatibilidade retroativa, inferir 'image' se type for omisso mas imageUrl existir
    String type = map['type'] as String? ?? 'text';
    if (map['type'] == null && imageUrl != null && imageUrl.isNotEmpty) {
      type = 'image';
    }

    return ChatMessage(
      id: id,
      text: map['text'] as String? ?? '',
      senderId: map['senderId'] as String? ?? '',
      senderName: map['senderName'] as String? ?? '',
      senderPlate: map['senderPlate'] as String? ?? '',
      sender: map['sender'] as String? ?? 'driver', // Default to 'driver' for legacy messages
      imageUrl: imageUrl,
      fileUrl: fileUrl,
      fileName: map['fileName'] as String?,
      type: type,
      driverId: map['driverId'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      isPending: isPending,
      status: map['status'] as String? ?? 'sent',
      timestamp: dateTime,
    );
  }
}

