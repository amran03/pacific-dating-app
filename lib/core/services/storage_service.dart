import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Kazi ya kupakia picha na kurudisha Download URL yake
  Future<String?> uploadProfileImage(String uid, File imageFile) async {
    try {
      // Tengeneza njia ya kipekee ya faili kwenye Storage (mfano: profile_images/uid.jpg)
      Reference ref = _storage.ref().child('profile_images').child('$uid.jpg');

      // Pakia faili
      UploadTask uploadTask = ref.putFile(imageFile);
      TaskSnapshot snapshot = await uploadTask;

      // Pata link ya kupakua (Download URL) ili tuweze kuihifadhi Firestore
      String downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print("Hitilafu wakati wa kupakia picha: $e");
      return null;
    }
  }
}