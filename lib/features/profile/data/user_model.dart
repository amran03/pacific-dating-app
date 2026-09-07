/// Muundo wa taarifa za mtumiaji mmoja mmoja (per-user).
class UserModel {
  final String uid;
  final String name;
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
  final String badgeTier;
  final int totalSpentCoins;
  final int? heightCm;
  final String? education;
  final String? occupation;
  final List<String> interests;
  final String? smokingHabit;
  final String? drinkingHabit;
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
    this.badgeTier = 'none',
    this.totalSpentCoins = 0,
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

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'name_lower': nameLower,
      'age': age,
      'birth_date': birthDate?.toIso8601String(),
      'gender': gender,
      'bio': bio,
      'interested_gender': interestedGender,
      'relationship_goal': relationshipGoal,
      'profile_image_url': profileImageUrl,
      'phone_number': phoneNumber,
      'auth_email': authEmail,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'fcm_token': fcmToken,
      'coins': coins,
      'badge_tier': badgeTier,
      'total_spent_coins': totalSpentCoins,
      'height_cm': heightCm,
      'education': education,
      'occupation': occupation,
      'interests': interests,
      'smoking_habit': smokingHabit,
      'drinking_habit': drinkingHabit,
      'chat_unlock_price': chatUnlockPrice,
      'location_enabled': locationEnabled,
      'notifications_enabled': notificationsEnabled,
      'is_profile_complete': isProfileComplete,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      age: map['age'] ?? 0,
      birthDate: map['birth_date'] != null ? DateTime.parse(map['birth_date']) : null,
      gender: map['gender'],
      bio: map['bio'],
      interestedGender: map['interested_gender'],
      relationshipGoal: map['relationship_goal'],
      profileImageUrl: map['profile_image_url'],
      phoneNumber: map['phone_number'],
      authEmail: map['auth_email'],
      location: map['location'],
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      fcmToken: map['fcm_token'],
      coins: map['coins'] ?? 0,
      badgeTier: map['badge_tier'] ?? 'none',
      totalSpentCoins: map['total_spent_coins'] ?? 0,
      heightCm: map['height_cm'],
      education: map['education'],
      occupation: map['occupation'],
      interests: map['interests'] != null ? List<String>.from(map['interests']) : const [],
      smokingHabit: map['smoking_habit'],
      drinkingHabit: map['drinking_habit'],
      chatUnlockPrice: map['chat_unlock_price'] ?? 0,
      locationEnabled: map['location_enabled'] ?? false,
      notificationsEnabled: map['notifications_enabled'] ?? false,
      isProfileComplete: map['is_profile_complete'] ?? false,
    );
  }

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
    String? badgeTier,
    int? totalSpentCoins,
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
      badgeTier: badgeTier ?? this.badgeTier,
      totalSpentCoins: totalSpentCoins ?? this.totalSpentCoins,
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
