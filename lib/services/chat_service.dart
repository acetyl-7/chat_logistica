import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/chat_message.dart';
import '../services/user_profile_service.dart';

class ChatService {
  ChatService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    UserProfileService? userProfileService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _userProfileService = userProfileService ?? UserProfileService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final UserProfileService _userProfileService;

  CollectionReference<Map<String, dynamic>> get _messagesRef =>
      _firestore.collection('messages');

  Future<void> sendMessage({
    required String text,
    required String senderId,
    String? imageUrl,
    String? fileUrl,
    String? fileName,
    String type = 'text',
    String? driverId,
    double? latitude,
    double? longitude,
  }) async {
    String senderName = '';
    String senderPlate = '';

    final user = _auth.currentUser;
    if (user != null) {
      final profile = await _userProfileService.getUserProfile(user.uid);
      if (profile != null) {
        senderName = profile.nome;
        senderPlate = profile.matricula;
      }
    }

    final message = ChatMessage(
      id: '',
      text: text.trim(),
      senderId: senderId,
      senderName: senderName,
      senderPlate: senderPlate,
      sender: 'driver', // Explicitly sent by the driver app
      imageUrl: imageUrl,
      fileUrl: fileUrl,
      fileName: fileName,
      type: type,
      driverId: driverId,
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
    );

    // O Documento do Firestore vai ser criado com todos os dados acima, mais o driverId caso seja providenciado
    await _messagesRef.add(message.toMap());

    if (type == 'image') {
      final uid = driverId ?? user?.uid;
      if (uid != null) {
        await _firestore.collection('users').doc(uid).set({
          'unreadImages': FieldValue.increment(1)
        }, SetOptions(merge: true));
      }
    }
  }

  Stream<List<ChatMessage>> messagesStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return _messagesRef
        .where('driverId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => ChatMessage.fromMap(
                  doc.id,
                  doc.data(),
                  isPending: doc.metadata.hasPendingWrites,
                ),
              )
              .toList(),
        );
  }
}

