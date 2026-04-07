import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  bool _isSyncing = false;

  void initialize() {
    // Listen to connectivity changes
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      bool isOnline = results.contains(ConnectivityResult.mobile) || 
                     results.contains(ConnectivityResult.wifi) ||
                     results.contains(ConnectivityResult.ethernet);
      if (isOnline) {
        syncPendingData();
      }
    });

    // Listen to Auth changes to trigger sync when user logs in
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        syncPendingData();
      }
    });

    // Trigger on startup
    syncPendingData();
  }

  Future<void> syncPendingData() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final driverId = user.uid;

      await _syncCollection('tasks', driverId, _syncTaskItem);
      await _syncCollection('refuels', driverId, _syncRefuelItem);
      await _syncCollection('incidents', driverId, _syncIncidentItem);

    } catch (e) {
      // Avoid printing to console if not using print, or use debugPrint
      // For now, silent failure or catch-all is better than crash
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncCollection(String collectionPath, String driverId, Future<void> Function(DocumentSnapshot) syncItemFn) async {
    final snapshot = await FirebaseFirestore.instance
        .collection(collectionPath)
        .where('driverId', isEqualTo: driverId)
        .where('needsImageSync', isEqualTo: true)
        .get();

    for (var doc in snapshot.docs) {
      await syncItemFn(doc);
    }
  }

  Future<void> _syncTaskItem(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final String? localPath = data['localImagePath'];
    final String? localOperationPath = data['localOperationImagePath'];
    
    if (localPath == null && localOperationPath == null) {
      // Nothing to sync, clear the flag
      await doc.reference.update({'needsImageSync': false});
      return;
    }

    bool hasErrors = false;
    final Map<String, dynamic> updates = {};

    try {
      if (localPath != null) {
        final file = File(localPath);
        if (await file.exists()) {
          final String storagePath = 'tasks/${data['driverId']}/${doc.id}_guia.jpg';
          final Reference ref = FirebaseStorage.instance.ref().child(storagePath);
          await ref.putFile(file);
          final String downloadUrl = await ref.getDownloadURL();
          
          updates['guiaImageUrl'] = downloadUrl;
          updates['localImagePath'] = FieldValue.delete();
          try { await file.delete(); } catch (_) {}
        } else {
          updates['localImagePath'] = FieldValue.delete();
          hasErrors = true;
        }
      }

      if (localOperationPath != null) {
        final opFile = File(localOperationPath);
        if (await opFile.exists()) {
          final String storagePath = 'tasks/${data['driverId']}/${doc.id}_operation.jpg';
          final Reference ref = FirebaseStorage.instance.ref().child(storagePath);
          await ref.putFile(opFile);
          final String downloadUrl = await ref.getDownloadURL();
          
          updates['operationImageUrl'] = downloadUrl;
          updates['localOperationImagePath'] = FieldValue.delete();
          try { await opFile.delete(); } catch (_) {}
        } else {
          updates['localOperationImagePath'] = FieldValue.delete();
          hasErrors = true;
        }
      }

      updates['needsImageSync'] = false;
      if (hasErrors) {
        updates['syncError'] = 'One or more local files not found';
      }

      if (updates.isNotEmpty) {
        await doc.reference.update(updates);
      }
    } catch (e) {
      // Log error or set error flag on document
      await doc.reference.update({'syncError': e.toString()});
    }
  }

  Future<void> _syncRefuelItem(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final String? localPath = data['localImagePath'];
    if (localPath == null) return;

    final file = File(localPath);
    if (!await file.exists()) {
      await doc.reference.update({
        'needsImageSync': false,
        'localImagePath': FieldValue.delete(),
        'syncError': 'Local file not found',
      });
      return;
    }

    try {
      final String timestampStr = DateTime.now().millisecondsSinceEpoch.toString();
      final String storagePath = 'refuels/${data['driverId']}/$timestampStr.jpg';
      final Reference ref = FirebaseStorage.instance.ref().child(storagePath);
      await ref.putFile(file);
      final String downloadUrl = await ref.getDownloadURL();

      await doc.reference.update({
        'receiptUrl': downloadUrl,
        'needsImageSync': false,
        'localImagePath': FieldValue.delete(),
      });

      await file.delete();
    } catch (e) {
      // Log error
    }
  }

  Future<void> _syncIncidentItem(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final List<dynamic>? localPaths = data['localImagePaths'];
    if (localPaths == null || localPaths.isEmpty) return;

    List<String> imageUrls = List<String>.from(data['imageUrls'] ?? []);
    final String timestampStr = DateTime.now().millisecondsSinceEpoch.toString();

    try {
      List<String> filesToDelete = [];
      for (int i = 0; i < localPaths.length; i++) {
        final String path = localPaths[i];
        final file = File(path);
        if (await file.exists()) {
          final String storagePath = 'incidents/${data['driverId']}/${timestampStr}_$i.jpg';
          final Reference ref = FirebaseStorage.instance.ref().child(storagePath);
          await ref.putFile(file);
          final String downloadUrl = await ref.getDownloadURL();
          imageUrls.add(downloadUrl);
          filesToDelete.add(path);
        }
      }

      await doc.reference.update({
        'imageUrls': imageUrls,
        'needsImageSync': false,
        'localImagePaths': FieldValue.delete(),
      });

      for (var path in filesToDelete) {
        try {
          await File(path).delete();
        } catch (e) {
          // Ignore delete errors to avoid breaking sync of other files
        }
      }
    } catch (e) {
      // Log error
    }
  }
}
