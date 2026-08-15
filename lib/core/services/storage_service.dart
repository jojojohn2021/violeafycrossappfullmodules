import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseStorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Upload an image file from a local path (Mobile platforms)
  Future<String> uploadMobileFile({
    required String localPath,
    required String storageFolder,
    required String fileName,
  }) async {
    try {
      final ref = _storage.ref().child('$storageFolder/$fileName');
      final uploadTask = ref.putFile(File(localPath));
      
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint('Firebase Storage Mobile Upload Error: $e');
      rethrow;
    }
  }

  // Upload raw bytes (Web platform / Mobile memory files)
  Future<String> uploadBytes({
    required Uint8List fileBytes,
    required String storageFolder,
    required String fileName,
    String contentType = 'image/jpeg',
  }) async {
    try {
      final ref = _storage.ref().child('$storageFolder/$fileName');
      final metadata = SettableMetadata(contentType: contentType);
      
      final uploadTask = ref.putData(fileBytes, metadata);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint('Firebase Storage Bytes Upload Error: $e');
      rethrow;
    }
  }
}
