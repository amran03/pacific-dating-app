/// Service for standardizing input validation across onboarding and profile screens.
class ValidationService {
  static final ValidationService _instance = ValidationService._internal();
  factory ValidationService() => _instance;
  ValidationService._internal();

  /// Validates that a name is not empty and has a reasonable length.
  String? validateName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return "Please enter your name.";
    }
    if (name.trim().length < 2) {
      return "Name must be at least 2 characters.";
    }
    if (name.trim().length > 50) {
      return "Name is too long.";
    }
    return null;
  }

  /// Validates that a phone number follows a basic numeric format.
  String? validatePhone(String? phone) {
    if (phone == null || phone.trim().isEmpty) {
      return "Please enter your phone number.";
    }
    final phoneRegex = RegExp(r'^\+?[0-9]{7,15}$');
    if (!phoneRegex.hasMatch(phone.trim())) {
      return "Please enter a valid phone number.";
    }
    return null;
  }

  /// Validates that the user is 18 years or older.
  String? validateAge(DateTime? birthday) {
    if (birthday == null) {
      return "Please select your date of birth.";
    }
    final today = DateTime.now();
    final age = today.year - birthday.year;
    if (today.month < birthday.month || (today.month == birthday.month && today.day < birthday.day)) {
      // Not yet had birthday this year
      if (age - 1 < 18) return "You must be 18 years or older.";
    } else {
      if (age < 18) return "You must be 18 years or older.";
    }
    return null;
  }

  /// Validates a user bio for length and content.
  String? validateBio(String? bio) {
    if (bio == null || bio.trim().isEmpty) {
      return "Please write a short bio.";
    }
    if (bio.trim().length < 10) {
      return "Bio is too short. Please tell us more about yourself.";
    }
    if (bio.trim().length > 500) {
      return "Bio is too long. Please shorten it (max 500 characters).";
    }
    return null;
  }
}