import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pacific_dating_app/core/constants/app_color.dart';
import 'package:pacific_dating_app/core/services/supabase_db_service.dart';
import 'package:pacific_dating_app/core/services/storage_service.dart';
import 'package:pacific_dating_app/core/services/validation_service.dart';
import 'package:pacific_dating_app/core/services/core_error_service.dart';
import 'package:pacific_dating_app/features/profile/data/user_model.dart';
import 'package:pacific_dating_app/features/auth/presentation/create_password_screen.dart';
import 'package:pacific_dating_app/screens/pacific_launch_screen.dart';

class SetupAccountScreen extends StatefulWidget {
  final String phoneNumber;

  const SetupAccountScreen({super.key, required this.phoneNumber});

  @override
  State<SetupAccountScreen> createState() => _SetupAccountScreenState();
}

class _SetupAccountScreenState extends State<SetupAccountScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  final int _totalSteps = 9;

  // Dynamic Theme Color state
  Color _themeColor = AppColors.primary;

  // Dynamic Gradient for Theme
  Gradient get _themeGradient => LinearGradient(
    colors: [
      _themeColor,
      _themeColor.withValues(
        alpha: ((_themeColor.r * 255.0).round().clamp(0, 255) + 40)
            .clamp(0, 255) /
            255.0,
      ),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // User Form Data State
  final TextEditingController _nameController = TextEditingController();
  DateTime? _selectedBirthDate;
  int _calculatedAge = 0;
  String? _selectedGender;
  File? _profileImage;
  final TextEditingController _bioController = TextEditingController();
  String? _interestedGender;
  String? _relationshipGoal;

  // Permissions State
  bool _locationGranted = false;
  bool _notificationGranted = false;
  bool _cameraGranted = false;
  bool _micGranted = false;
  bool _mediaGranted = false;
  double? _latitude;
  double? _longitude;
  String? _fcmToken;

  final ImagePicker _picker = ImagePicker();
  final SupabaseDbService _dbService = SupabaseDbService();
  final StorageService _storageService = StorageService();
  bool _isSaving = false;

  // Dynamic Relationship Goals based on Gender
  List<String> get _relationshipGoals {
    if (_selectedGender == "Female") {
      return [
        "Boyfriend",
        "Husband",
        "Casual Dating",
        "Serious Relationship",
        "New Friends",
        "Not Sure Yet"
      ];
    } else {
      return [
        "Girlfriend",
        "Wife",
        "Casual Dating",
        "Serious Relationship",
        "New Friends",
        "Not Sure Yet"
      ];
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  int _calculateAge(DateTime birthDate) {
    DateTime today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  void _showAgeConfirmationDialog(int age, VoidCallback onConfirmed) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          elevation: 10,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            "You are $age?",
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: _themeColor),
          ),
          content: const Text(
            "Please confirm your age is correct. It will be shown on your profile and cannot be changed after registration.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4, fontWeight: FontWeight.w300),
          ),
          actionsAlignment: MainAxisAlignment.spaceAround,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Badilisha", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _themeColor,
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () {
                Navigator.pop(context);
                onConfirmed();
              },
              child: const Text("Yes, it is correct", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70, // Compress image to 70% quality to reduce upload size
    );
    if (pickedFile != null) {
      setState(() {
        _profileImage = File(pickedFile.path);
      });
    }
  }

  void _nextStep() async {
    if (_currentStep == 0) {
      final String? error = ValidationService().validateName(_nameController.text);
      if (error != null) {
        CoreErrorService().showError(context, error);
        return;
      }
    }

    if (_currentStep == 1) {
      final String? error = ValidationService().validateAge(_selectedBirthDate);
      if (error != null) {
        CoreErrorService().showError(context, error);
        return;
      }
      _calculatedAge = _calculateAge(_selectedBirthDate!);
      _showAgeConfirmationDialog(_calculatedAge, () {
        _goToNextPage();
      });
      return;
    }

    if (_currentStep == 2 && _selectedGender == null) {
      CoreErrorService().showError(context, "Please select your gender.");
      return;
    }

    // Picha sasa si lazima (optional) - Firebase Storage inahitaji Blaze
    // plan (billing) ambayo si lazima to MVP. User anaweza kuiweka
    // baadaye kwenye Profile Settings.

    if (_currentStep == 4) {
      final String? error = ValidationService().validateBio(_bioController.text);
      if (error != null) {
        CoreErrorService().showError(context, error);
        return;
      }
    }

    if (_currentStep == 5 && _interestedGender == null) {
      CoreErrorService().showError(context, "Please select the gender you are interested in.");
      return;
    }

    if (_currentStep == 6 && _relationshipGoal == null) {
      CoreErrorService().showError(context, "Please select the type of relationship you are looking for.");
      return;
    }

    if (_currentStep < _totalSteps - 1) {
      _goToNextPage();
    } else {
      await _finishSetup();
    }
  }

  void _goToNextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep++);
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep--);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _finishSetup() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    // Hatua ya mwisho kabisa: kama bado hakuna akaunti ya Supabase
    // (mtumiaji hajaweka password bado), mfungulie sasa hivi skrini ya
    // kutengeneza password. SetupAccountScreen inabaki kwenye stack, hivyo
    // taarifa zote za profile alizoshajaza (jina, picha, bio n.k.) hazipotei.
    User? currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      final bool? accountCreated = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => CreatePasswordScreen(phoneNumber: widget.phoneNumber),
        ),
      );

      if (accountCreated != true || !mounted) {
        setState(() => _isSaving = false);
        return;
      }

      currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        _showSnackBar("Failed to create account. Please try again.");
        setState(() => _isSaving = false);
        return;
      }
    }

    try {
      String? imageUrl;

      // 1. Pandisha picha ya profile kwenye Storage (ikiwa mtumiaji ameweka moja)
      if (_profileImage != null) {
        imageUrl = await _storageService.uploadProfileImage(currentUser.id, _profileImage!);
      }

      // 2. Kusanya taarifa zote za hatua za usajili kuwa UserModel moja
      final UserModel userModel = UserModel(
        uid: currentUser.id,
        name: _nameController.text.trim(),
        age: _calculatedAge,
        birthDate: _selectedBirthDate,
        gender: _selectedGender,
        bio: _bioController.text.trim(),
        interestedGender: _interestedGender,
        relationshipGoal: _relationshipGoal,
        profileImageUrl: imageUrl,
        phoneNumber: widget.phoneNumber,
        latitude: _latitude,
        longitude: _longitude,
        fcmToken: _fcmToken,
        locationEnabled: _locationGranted,
        notificationsEnabled: _notificationGranted,
        isProfileComplete: true,
      );

      // 3. Hifadhi Supabase 'users' table.
      await _dbService.saveUserProfile(userModel);

      if (!mounted) return;

      _showSnackBar("Your account is fully complete! 🎉", color: Colors.green);

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const PacificLaunchScreen()),
            (route) => false,
      );
    } catch (e) {
      CoreErrorService().showError(
        context,
        CoreErrorService().mapExceptionToMessage(e),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message, {Color color = Colors.redAccent}) {
    CoreErrorService().showError(context, message, color: color);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          onPressed: _previousStep,
        ),
        title: Text(
          "Hatua ${_currentStep + 1} ya $_totalSteps",
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: (_currentStep + 1) / _totalSteps,
                  backgroundColor: Colors.grey.shade200,
                  color: _themeColor,
                  minHeight: 10,
                ),
              ),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildNameStep(),
                  _buildBirthdayStep(),
                  _buildIdentifyAsStep(),
                  _buildAddPhotoStep(),
                  _buildDescribeYourselfStep(),
                  _buildInterestedGenderStep(),
                  _buildRelationshipGoalStep(),
                  _buildPermissionsStep(),
                  _buildFinalCompletionStep(),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 15,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: _themeGradient,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: _themeColor.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: _isSaving ? null : _nextStep,
                    child: _isSaving
                        ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                        : Text(
                      _currentStep == _totalSteps - 1 ? "Continue ▶" : "Continue ▶",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- STEPS ---

  Widget _buildNameStep() {
    return _buildStepLayout(
      title: "Your First Name?",
      subtitle: "Enter the name you want to use. This is the main name other people will see on your profile.",
      child: Container(
        decoration: _buildBoxDecoration(),
        child: TextField(
          controller: _nameController,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            hintText: "Mfano: Baraka, Sophia...",
            hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w300),
            filled: true,
            fillColor: Colors.white,
            prefixIcon: Icon(Icons.person_outline_rounded, color: _themeColor),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: _themeColor, width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBirthdayStep() {
    return _buildStepLayout(
      title: "Tarehe ya Kuzaliwa",
      subtitle: "We use this date to calculate your age. Watu wengine wataona umri wako pekee (mfano: 24) na sio tarehe kamili ya kuzaliwa.",
      child: InkWell(
        onTap: () async {
          DateTime? picked = await showDatePicker(
            context: context,
            initialDate: DateTime(2002),
            firstDate: DateTime(1950),
            lastDate: DateTime(2008),
          );
          if (picked != null) {
            setState(() => _selectedBirthDate = picked);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: _buildBoxDecoration(),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _selectedBirthDate == null
                    ? "Bonyeza hapa kuchagua Tarehe"
                    : "${_selectedBirthDate!.day} / ${_selectedBirthDate!.month} / ${_selectedBirthDate!.year}",
                style: TextStyle(
                  fontSize: 17,
                  color: _selectedBirthDate == null ? Colors.grey.shade500 : AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Icon(Icons.calendar_today_rounded, color: _themeColor, size: 26),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdentifyAsStep() {
    return _buildStepLayout(
      title: "Your Gender",
      subtitle: "Select your gender to help the system find the right people for you.",
      child: Column(
        children: [
          _buildGenderTile("Mwanaume (Man)", "Male"),
          const SizedBox(height: 16),
          _buildGenderTile("Mwanamke (Woman)", "Female"),
        ],
      ),
    );
  }

  Widget _buildGenderTile(String label, String genderValue) {
    bool isSelected = _selectedGender == genderValue;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedGender = genderValue;
          _themeColor = (genderValue == "Male") ? Colors.blue.shade700 : AppColors.primary;
          // Reset relationship goal when gender changes to prevent invalid selections
          _relationshipGoal = null;
        });
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: isSelected ? _themeColor : Colors.transparent, width: 2.5),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: isSelected ? _themeColor.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.06),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isSelected ? _themeColor : AppColors.textPrimary,
              ),
            ),
            if (isSelected) Icon(Icons.check_circle_rounded, color: _themeColor, size: 26),
          ],
        ),
      ),
    );
  }

  Widget _buildAddPhotoStep() {
    return _buildStepLayout(
      title: "Your Main Photo",
      subtitle: "Add a clear photo of your face. Good photos increase your likes by over 80%.",
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              width: 220,
              height: 280,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: _themeColor.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: _profileImage != null
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.file(_profileImage!, fit: BoxFit.cover),
              )
                  : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _themeColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.add_a_photo_rounded, size: 48, color: _themeColor),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Tap to Add Photo",
                    style: TextStyle(color: _themeColor, fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: Text(
              "No need to add a photo now - you can add one later in your Profile.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescribeYourselfStep() {
    return _buildStepLayout(
      title: "Jieleze Kidogo (Bio)",
      subtitle: "Write a few things about yourself, like what you enjoy, your work, or the lifestyle you prefer.",
      child: Container(
        decoration: _buildBoxDecoration(),
        child: TextField(
          controller: _bioController,
          maxLines: 5,
          maxLength: 150,
          style: const TextStyle(fontSize: 16, height: 1.4),
          decoration: InputDecoration(
            hintText: "Mfano: Napenda kusafiri, kusoma vitabu, na kusikiliza muziki wa taratibu jioni...",
            hintStyle: TextStyle(color: Colors.grey.shade400),
            filled: true,
            fillColor: Colors.white,
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: _themeColor, width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInterestedGenderStep() {
    return _buildStepLayout(
      title: "Unavutiwa na Nani?",
      subtitle: "Choose the group of people you want to see while swiping and finding friends.",
      child: Column(
        children: [
          _buildSelectableOption("Wanaume (Men)", _interestedGender, (val) => setState(() => _interestedGender = val)),
          const SizedBox(height: 14),
          _buildSelectableOption("Wanawake (Women)", _interestedGender, (val) => setState(() => _interestedGender = val)),
          const SizedBox(height: 14),
          _buildSelectableOption("Wote (Everyone)", _interestedGender, (val) => setState(() => _interestedGender = val)),
        ],
      ),
    );
  }

  Widget _buildRelationshipGoalStep() {
    return _buildStepLayout(
      title: "Unatafuta Nini Hapa?",
      subtitle: "State your intention clearly so you can be matched with people who share the same goals.",
      child: Column(
        children: _relationshipGoals.map((goal) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: _buildSelectableOption(goal, _relationshipGoal, (val) => setState(() => _relationshipGoal = val)),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPermissionsStep() {
    return _buildStepLayout(
      title: "Important Permissions",
      subtitle: "Allow these services so we can show you people near you and notify you when you get a new match.",
      child: Column(
        children: [
          _buildPermissionSwitch(
            title: "Location Access",
            subtitle: "Helps find and show people who are geographically close to you.",
            icon: Icons.location_on_rounded,
            systemPermission: Permission.location,
            value: _locationGranted,
            onGranted: () async {
              // Chukua GPS coordinates halisi ili ziweze kutumika
              // baadaye kuhesabu umbali kati yako na watumiaji
              // wengine kwenye Discover.
              try {
                final position = await Geolocator.getCurrentPosition(
                  locationSettings: const LocationSettings(
                    accuracy: LocationAccuracy.medium,
                  ),
                );
                _latitude = position.latitude;
                _longitude = position.longitude;
                setState(() => _locationGranted = true);
              } catch (e) {
                _showSnackBar("Failed to get your location: $e");
              }
            },
          ),
          const SizedBox(height: 16),
          _buildPermissionSwitch(
            title: "Notifications",
            subtitle: "Receive instant messages and notifications about likes from others.",
            icon: Icons.notifications_active_rounded,
            systemPermission: Permission.notification,
            value: _notificationGranted,
            onGranted: () async {
              setState(() => _notificationGranted = true);
            },
          ),
          const SizedBox(height: 16),
          _buildPermissionSwitch(
            title: "Camera & Media",
            subtitle: "Take photos and pick images from your gallery for your profile and chats.",
            icon: Icons.photo_camera_rounded,
            systemPermission: Permission.camera,
            value: _cameraGranted,
            onGranted: () async {
              setState(() => _cameraGranted = true);
              // Ruhusa ya gallery/media inaombwa mara moja tu
              // (Android 13+: READ_MEDIA_IMAGES; zaidi: storage).
              if (_mediaGranted) return;
              final media = await Permission.photos.request();
              setState(() => _mediaGranted = media.isGranted || media.isLimited);
            },
          ),
          const SizedBox(height: 16),
          _buildPermissionSwitch(
            title: "Microphone (Voice Recording)",
            subtitle: "Needed for voice notes, voice calls and video calls.",
            icon: Icons.mic_rounded,
            systemPermission: Permission.microphone,
            value: _micGranted,
            onGranted: () async {
              setState(() => _micGranted = true);
            },
          ),
        ],
      ),
    );
  }

  // --- PAGE 9: FINAL COMPLETION PAGE ---
  Widget _buildFinalCompletionStep() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28.0),
              decoration: BoxDecoration(
                gradient: _themeGradient,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: _themeColor.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: _profileImage != null
                            ? ClipRRect(
                          borderRadius: BorderRadius.circular(50),
                          child: Image.file(_profileImage!, fit: BoxFit.cover),
                        )
                            : Icon(Icons.person, size: 60, color: _themeColor),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Welcome, ${_nameController.text.isNotEmpty ? _nameController.text : 'Guest'}!",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      "Your Profile Is 100% Ready",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20.0),
              decoration: _buildBoxDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.stars_rounded, color: _themeColor, size: 28),
                      const SizedBox(width: 10),
                      const Text(
                        "Muhtasari wa Profile",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _buildSummaryRow(Icons.cake_rounded, "Umri", "$_calculatedAge Miaka"),
                  _buildSummaryRow(Icons.wc_rounded, "Unatafuta", _interestedGender ?? "Haijachaguliwa"),
                  _buildSummaryRow(Icons.favorite_rounded, "Lengo", _relationshipGoal ?? "Haijachaguliwa"),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Text(
              "Tap 'Continue' below to set your final password, then start seeing people around you and begin your dating journey!",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.5, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildStepLayout({required String title, required String subtitle, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
                height: 1.5,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 28),
            child,
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectableOption(String label, String? currentValue, Function(String) onSelect) {
    bool isSelected = currentValue == label;
    return GestureDetector(
      onTap: () => onSelect(label),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: isSelected ? _themeColor : Colors.transparent, width: 2.5),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: isSelected ? _themeColor.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: isSelected ? _themeColor : AppColors.textPrimary,
              ),
            ),
            if (isSelected) Icon(Icons.check_circle_rounded, color: _themeColor, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionSwitch({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required Future<void> Function() onGranted,
    Permission? systemPermission,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _buildBoxDecoration(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _themeColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _themeColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3, fontWeight: FontWeight.w300),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: _themeColor,
            onChanged: (val) async {
              if (!val) return;
              // Hakuna ruhusa ya system inayoombwa — chagua tu (inline switch).
              final permission = systemPermission;
              if (permission == null) {
                await onGranted();
                return;
              }

              final status = await permission.request();
              if (status.isGranted || status.isLimited) {
                await onGranted();
              } else if (status.isPermanentlyDenied) {
                _showSnackBar(
                  "You previously denied this permission. Open Settings to enable it.",
                );
                await openAppSettings();
              } else {
                _showSnackBar(
                  "This feature works best with the permission enabled.",
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: _themeColor),
          const SizedBox(width: 12),
          Text("$title: ", style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _buildBoxDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 15,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }
}