import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_profile.dart';

class UserProfileService {
  UserProfileService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _usersRef =>
      _firestore.collection('users');

  Future<void> saveUserProfile(UserProfile profile) {
    return _usersRef.doc(profile.uid).set(
          profile.toMap(),
          SetOptions(merge: true),
        );
  }

  Future<UserProfile?> getUserProfile(String uid) async {
    final doc = await _usersRef.doc(uid).get();
    if (!doc.exists) {
      return null;
    }
    final data = doc.data();
    if (data == null) return null;
    return UserProfile.fromMap(data);
  }
}