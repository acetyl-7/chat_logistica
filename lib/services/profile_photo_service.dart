import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ProfilePhotoService {
  ProfilePhotoService({
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  Future<String> uploadProfilePhoto(File file) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Sem utilizador autenticado');
    }

    final ref =
        _storage.ref().child('profile_photos').child('${user.uid}.jpg');

    await ref.putFile(file);
    return ref.getDownloadURL();
  }
}

