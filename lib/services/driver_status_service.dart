import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DriverStatusService {
  DriverStatusService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _statusRef =>
      _firestore.collection('driver_status');

  Future<void> updateStatus(
    String status, {
    double? latitude,
    double? longitude,
    String? tractorPlate,
    String? trailerPlate,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Sem utilizador autenticado');
    }

    final data = <String, dynamic>{
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      'email': user.email,
    };

    if (latitude != null && longitude != null) {
      data['latitude'] = latitude;
      data['longitude'] = longitude;
    }

    if (tractorPlate != null && tractorPlate.isNotEmpty) {
      data['tractorPlate'] = tractorPlate;
    }
    if (trailerPlate != null && trailerPlate.isNotEmpty) {
      data['trailerPlate'] = trailerPlate;
    }

    await _statusRef.doc(user.uid).set(
      data,
      SetOptions(merge: true),
    );
  }

  Stream<String?> currentStatusStream() {
    final user = _auth.currentUser;
    if (user == null) {
      return const Stream.empty();
    }

    return _statusRef.doc(user.uid).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      return data['status'] as String?;
    });
  }
}