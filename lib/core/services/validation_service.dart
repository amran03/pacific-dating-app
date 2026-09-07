/// Service for standardizing input validation across onboarding and profile screens.
class ValidationService {
  static final ValidationService _instance = ValidationService._internal();
  factory ValidationService() => _instance;
  ValidationService._internal();

  /// Validates that a name is not empty and has a reasonable length.
  String? validateName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return "Tafadhali weka jina lako.";
    }
    if (name.trim().length < 2) {
      return "Jina lazima liwe na herufi angalau mbili.";
    }
    if (name.trim().length > 50) {
      return "Jina ni refu mno.";
    }
    return null;
  }

  /// Validates that a phone number follows a basic numeric format.
  String? validatePhone(String? phone) {
    if (phone == null || phone.trim().isEmpty) {
      return "Tafadhali weka namba ya simu.";
    }
    final phoneRegex = RegExp(r'^\+?[0-9]{7,15}$');
    if (!phoneRegex.hasMatch(phone.trim())) {
      return "Tafadhali weka namba ya simu sahihi.";
    }
    return null;
  }

  /// Validates that the user is 18 years or older.
  String? validateAge(DateTime? birthday) {
    if (birthday == null) {
      return "Tafadhali chagua tarehe ya kuzaliwa.";
    }
    final today = DateTime.now();
    final age = today.year - birthday.year;
    if (today.month < birthday.month || (today.month == birthday.month && today.day < birthday.day)) {
      // Not yet had birthday this year
      if (age - 1 < 18) return "Lazima uwe na umri wa miaka 18 au zaidi.";
    } else {
      if (age < 18) return "Lazima uwe na umri wa miaka 18 au zaidi.";
    }
    return null;
  }

  /// Validates a user bio for length and content.
  String? validateBio(String? bio) {
    if (bio == null || bio.trim().isEmpty) {
      return "Tafadhali andika utambulisho mfupi (bio).";
    }
    if (bio.trim().length < 10) {
      return "Bio ni fupi mno. Tafadhali eleza zaidi kujikufanya ujulikane.";
    }
    if (bio.trim().length > 500) {
      return "Bio ni refu mno. Tafadhali ifupishe (max 500 characters).";
    }
    return null;
  }
}