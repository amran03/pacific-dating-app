import 'package:cloud_firestore/cloud_firestore.dart';

/// Muundo wa taarifa za mtumiaji mmoja mmoja (per-user), sio static/shared.
/// Fields zote hapa zinaendana na kile kinachokusanywa kwenye
/// SetupAccountScreen (jina, umri, jinsia, bio, picha, n.k.)
class UserModel {
  final String uid;
  final String name;
  // Toleo la jina lililowekwa herufi ndogo zote - hutumika kwa ajili ya
  // utafutaji (search) kwenye Firestore bila kujali herufi kubwa/ndogo.
  String get nameLower => name.toLowerCase();
  final int age;
  final DateTime? birthDate;
  final String? gender;
  final String? bio;
  final String? interestedGender;
  final String? relationshipGoal;
  final String? profileImageUrl;
  final String? phoneNumber;
  final String? authEmail;
  final String? location;
  final double? latitude;
  final double? longitude;
  final String? fcmToken;
  final int coins;
  // Fields za ziada zinazofanana na dating apps nyingine
  final int? heightCm;
  final String? education;
  final String? occupation;
  final List<String> interests;
  final String? smokingHabit;
  final String? drinkingHabit;
  // Bei (Coins) ambayo MTU MWINGINE anatakiwa alipe kufungua chat na
  // mtumiaji huyu (0 = bure kabisa). Mmiliki wa profile ndiye anayeweka.
  final int chatUnlockPrice;
  final bool locationEnabled;
  final bool notificationsEnabled;
  final bool isProfileComplete;

  UserModel({
    required this.uid,
    required this.name,
    required this.age,
    this.birthDate,
    this.gender,
    this.bio,
    this.interestedGender,
    this.relationshipGoal,
    this.profileImageUrl,
    this.phoneNumber,
    this.authEmail,
    this.location,
    this.latitude,
    this.longitude,
    this.fcmToken,
    this.coins = 0,
    this.heightCm,
    this.education,
    this.occupation,
    this.interests = const [],
    this.smokingHabit,
    this.drinkingHabit,
    this.chatUnlockPrice = 0,
    this.locationEnabled = false,
    this.notificationsEnabled = false,
    this.isProfileComplete = false,
  });

  /// Inabadilisha object hii kuwa Map ili iweze kuhifadhiwa Firestore
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'nameLower': nameLower,
      'age': age,
      'birthDate': birthDate != null ? Timestamp.fromDate(birthDate!) : null,
      'gender': gender,
      'bio': bio,
      'interestedGender': interestedGender,
      'relationshipGoal': relationshipGoal,
      'profileImageUrl': profileImageUrl,
      'phoneNumber': phoneNumber,
      'authEmail': authEmail,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'fcmToken': fcmToken,
      'coins': coins,
      'heightCm': heightCm,
      'education': education,
      'occupation': occupation,
      'interests': interests,
      'smokingHabit': smokingHabit,
      'drinkingHabit': drinkingHabit,
      'chatUnlockPrice': chatUnlockPrice,
      'locationEnabled': locationEnabled,
      'notificationsEnabled': notificationsEnabled,
      'isProfileComplete': isProfileComplete,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Inasoma Map kutoka Firestore na kuitengeneza kuwa UserModel
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      age: map['age'] ?? 0,
      birthDate: map['birthDate'] != null ? (map['birthDate'] as Timestamp).toDate() : null,
      gender: map['gender'],
      bio: map['bio'],
      interestedGender: map['interestedGender'],
      relationshipGoal: map['relationshipGoal'],
      profileImageUrl: map['profileImageUrl'],
      phoneNumber: map['phoneNumber'],
      authEmail: map['authEmail'],
      location: map['location'],
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      fcmToken: map['fcmToken'],
      coins: map['coins'] ?? 0,
      heightCm: map['heightCm'],
      education: map['education'],
      occupation: map['occupation'],
      interests: map['interests'] != null ? List<String>.from(map['interests']) : const [],
      smokingHabit: map['smokingHabit'],
      drinkingHabit: map['drinkingHabit'],
      chatUnlockPrice: map['chatUnlockPrice'] ?? 0,
      locationEnabled: map['locationEnabled'] ?? false,
      notificationsEnabled: map['notificationsEnabled'] ?? false,
      isProfileComplete: map['isProfileComplete'] ?? false,
    );
  }

  /// Husaidia ku-update fields chache tu bila kupoteza zilizopo (mfano
  /// unapotaka kubadilisha bio pekee bila kuathiri picha/jina)
  UserModel copyWith({
    String? name,
    int? age,
    DateTime? birthDate,
    String? gender,
    String? bio,
    String? interestedGender,
    String? relationshipGoal,
    String? profileImageUrl,
    String? location,
    double? latitude,
    double? longitude,
    String? fcmToken,
    int? coins,
    int? heightCm,
    String? education,
    String? occupation,
    List<String>? interests,
    String? smokingHabit,
    String? drinkingHabit,
    int? chatUnlockPrice,
    bool? locationEnabled,
    bool? notificationsEnabled,
    bool? isProfileComplete,
  }) {
    return UserModel(
      uid: uid,
      name: name ?? this.name,
      age: age ?? this.age,
      birthDate: birthDate ?? this.birthDate,
      gender: gender ?? this.gender,
      bio: bio ?? this.bio,
      interestedGender: interestedGender ?? this.interestedGender,
      relationshipGoal: relationshipGoal ?? this.relationshipGoal,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      phoneNumber: phoneNumber,
      authEmail: authEmail,
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      fcmToken: fcmToken ?? this.fcmToken,
      coins: coins ?? this.coins,
      heightCm: heightCm ?? this.heightCm,
      education: education ?? this.education,
      occupation: occupation ?? this.occupation,
      interests: interests ?? this.interests,
      smokingHabit: smokingHabit ?? this.smokingHabit,
      drinkingHabit: drinkingHabit ?? this.drinkingHabit,
      chatUnlockPrice: chatUnlockPrice ?? this.chatUnlockPrice,
      locationEnabled: locationEnabled ?? this.locationEnabled,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      isProfileComplete: isProfileComplete ?? this.isProfileComplete,
    );
  }
}