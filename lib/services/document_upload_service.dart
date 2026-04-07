import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart'; // import for debugPrint
import 'package:image_picker/image_picker.dart';

import 'chat_service.dart';
import 'location_service.dart';

class DocumentUploadService {
  DocumentUploadService({
    FirebaseAuth? auth,
    FirebaseStorage? storage,
    ChatService? chatService,
    LocationService? locationService,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _chatService = chatService ?? ChatService(),
        _locationService = locationService ?? LocationService();

  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final ChatService _chatService;
  final LocationService _locationService;

  Future<void> uploadDriverDocument(XFile file) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Sem utilizador autenticado');
    }

    // Gerar um nome único e simples (ex: DateTime.now().millisecondsSinceEpoch.jpg)
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';

    final ref = _storage
        .ref()
        .child('chat_images')
        .child(user.uid)
        .child(fileName);

    try {
      final fileObj = File(file.path);
      if (!await fileObj.exists()) {
        throw Exception('Arquivo inexistente.');
      }
      // Uso de await corretamente no putFile e getDownloadURL
      await ref.putFile(fileObj);
      final url = await ref.getDownloadURL();

      double? latitude;
      double? longitude;
      final position = await _locationService.getCurrentPosition();
      if (position != null) {
        latitude = position.latitude;
        longitude = position.longitude;
      }

      await _chatService.sendMessage(
        text: 'Documento enviado',
        senderId: user.uid,
        fileUrl: url,
        type: 'image',
        driverId: user.uid,
        latitude: latitude,
        longitude: longitude,
      );
    } catch (e) {
      // Imprimir o erro no console se falhar
      debugPrint('Erro ao fazer upload do documento: $e');
      rethrow;
    }
  }

  Future<void> uploadChatDocument(PlatformFile file) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Sem utilizador autenticado');
    }

    if (file.path == null) {
      throw Exception('Caminho do ficheiro inválido');
    }

    final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9.\-_]'), '_');
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_$safeName';

    final ref = _storage
        .ref()
        .child('chat_attachments')
        .child(user.uid)
        .child(fileName);

    try {
      final fileObj = File(file.path!);
      if (!await fileObj.exists()) {
        throw Exception('Arquivo inexistente.');
      }
      
      await ref.putFile(fileObj);
      final url = await ref.getDownloadURL();

      double? latitude;
      double? longitude;
      final position = await _locationService.getCurrentPosition();
      if (position != null) {
        latitude = position.latitude;
        longitude = position.longitude;
      }

      await _chatService.sendMessage(
        text: file.name,
        senderId: user.uid,
        fileUrl: url,
        fileName: file.name,
        type: 'document',
        driverId: user.uid,
        latitude: latitude,
        longitude: longitude,
      );
    } catch (e) {
      debugPrint('Erro ao fazer upload do anexo: $e');
      rethrow;
    }
  }
}

