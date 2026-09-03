import 'package:cloud_firestore/cloud_firestore.dart';
import '../../features/profile/data/user_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Kuhifadhi au Kusasisha taarifa za mtumiaji
  // merge: true inahakikisha fields zilizopo tayari (mfano phoneNumber,
  // authEmail zilizowekwa na CreatePasswordScreen) hazifutiki.
  Future<void> saveUserProfile(UserModel user) async {
    await _db.collection('users').doc(user.uid).set(user.toMap(), SetOptions(merge: true));
  }

  // Kusoma taarifa za mtumiaji
  Future<UserModel?> getUserProfile(String uid) async {
    DocumentSnapshot doc = await _db.collection('users').doc(uid).get();
    if (doc.exists) {
      return UserModel.fromMap(doc.data() as Map<String, dynamic>);
    }
    return null;
  }
}