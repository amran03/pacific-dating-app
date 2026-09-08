import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pacific_dating_app/core/constants/app_color.dart';
import 'package:pacific_dating_app/core/services/supabase_db_service.dart';
import 'package:pacific_dating_app/core/services/storage_service.dart';
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

  Color _themeColor = AppColors.primary;

  Gradient get _themeGradient => LinearGradient(
    colors: [
      _themeColor,
      _themeColor.withValues(alpha: 0.8),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  final TextEditingController _nameController = TextEditingController();
  DateTime? _selectedBirthDate;
  int _calculatedAge = 0;
  String? _selectedGender;
  File? _profileImage;
  final TextEditingController _bioController = TextEditingController();
  String? _interestedGender;
  String? _relationshipGoal;

  bool _locationGranted = false;
  bool _notificationGranted = false;

  final ImagePicker _picker = ImagePicker();
  final SupabaseDbService _dbService = SupabaseDbService();
  final StorageService _storageService = StorageService();
  bool _isSaving = false;

  List<String> get _relationshipGoals {
    if (_selectedGender == "Female") {
      return [
        "Boyfriend 🕺",
        "Husband 💍",
        "Casual Dating 🥂",
        "Serious Relationship ❤️",
        "New Friends 🤝",
        "Not Sure Yet 🤔"
      ];
    } else {
      return [
        "Girlfriend 💃",
        "Wife 💍",
        "Casual Dating 🥂",
        "Serious Relationship ❤️",
        "New Friends 🤝",
        "Not Sure Yet 🤔"
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            "Una miaka $age? 🎂",
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: _themeColor),
          ),
          content: const Text(
            "Tafadhali hakikisha umri wako ni sahihi. Maelezo haya yatatumiwa kuonyesha umri wako kwenye profile na huwezi kuyabadilisha baada ya kukamilisha usajili.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () {
                Navigator.pop(context);
                onConfirmed();
              },
              child: const Text("Ndiyo, ni Sahihi", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _profileImage = File(pickedFile.path);
      });
    }
  }

  void _nextStep() async {
    if (_currentStep == 0 && _nameController.text.trim().isEmpty) {
      _showSnackBar("Tafadhali ingiza jina lako la kwanza kuendelea.");
      return;
    }
    if (_currentStep == 1) {
      if (_selectedBirthDate == null) {
        _showSnackBar("Tafadhali chagua tarehe yako ya kuzaliwa.");
        return;
      }
      _calculatedAge = _calculateAge(_selectedBirthDate!);
      _showAgeConfirmationDialog(_calculatedAge, () {
        _goToNextPage();
      });
      return;
    }
    if (_currentStep == 2 && _selectedGender == null) {
      _showSnackBar("Tafadhali chagua jinsia yako.");
      return;
    }
    if (_currentStep == 3 && _profileImage == null) {
      _showSnackBar("Tafadhali weka picha yako kuu ya profile.");
      return;
    }
    if (_currentStep == 4 && _bioController.text.trim().isEmpty) {
      _showSnackBar("Tafadhali andika maelezo mafupi kukuhusu.");
      return;
    }
    if (_currentStep == 5 && _interestedGender == null) {
      _showSnackBar("Tafadhali chagua jinsia unayovutiwa nayo.");
      return;
    }
    if (_currentStep == 6 && _relationshipGoal == null) {
      _showSnackBar("Tafadhali chagua aina ya uhusiano unayotafuta.");
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
        _showSnackBar("Imeshindikana kutengeneza akaunti. Jaribu tena.");
        setState(() => _isSaving = false);
        return;
      }
    }

    try {
      String? imageUrl;
      if (_profileImage != null) {
        imageUrl = await _storageService.uploadProfileImage(currentUser.id, _profileImage!);
      }

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
        locationEnabled: _locationGranted,
        notificationsEnabled: _notificationGranted,
        isProfileComplete: true,
      );

      await _dbService.saveUserProfile(userModel);

      if (!mounted) return;
      _showSnackBar("Akaunti yako imekamilika kikamilifu! 🎉", color: Colors.green);
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const PacificLaunchScreen()),
            (route) => false,
      );
    } catch (e) {
      _showSnackBar("Imeshindikana kuhifadhi profile: ${e.toString()}");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message, {Color color = Colors.redAccent}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
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
                      _currentStep == _totalSteps - 1 ? "Continue ▶" : "Endelea ▶",
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
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -0.5),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.5, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 28),
            child,
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildNameStep() {
    return _buildStepLayout(
      title: "Jina Lako la Kwanza? ✍️",
      subtitle: "Ingiza jina unalotaka kutumia. Hili ndilo jina kuu litakalotokea kwenye profile yako kwa watu wengine.",
      child: Container(
        decoration: _buildBoxDecoration(),
        child: TextField(
          controller: _nameController,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: "Mfano: Baraka, Sophia...",
            hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.normal),
            filled: true,
            fillColor: Colors.white,
            prefixIcon: Icon(Icons.person_outline_rounded, color: _themeColor),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: _themeColor, width: 2)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          ),
        ),
      ),
    );
  }

  Widget _buildBirthdayStep() {
    return _buildStepLayout(
      title: "Tarehe ya Kuzaliwa 🎂",
      subtitle: "Tunatumia tarehe hii kukokotoa umri wako. Watu wengine wataona umri wako pekee (mfano: 24) na sio tarehe kamili ya kuzaliwa.",
      child: InkWell(
        onTap: () async {
          DateTime? picked = await showDatePicker(
            context: context,
            initialDate: DateTime(2002),
            firstDate: DateTime(1950),
            lastDate: DateTime(2008),
          );
          if (picked != null) setState(() => _selectedBirthDate = picked);
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
                style: TextStyle(fontSize: 17, color: _selectedBirthDate == null ? Colors.grey.shade500 : AppColors.textPrimary, fontWeight: FontWeight.bold),
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
      title: "Jinsia Yako 👤",
      subtitle: "Chagua jinsia yako ili kusaidia mfumo kukutafutia watu sahihi kulingana na matakwa yako.",
      child: Column(
        children: [
          _buildGenderTile("Mwanaume (Man) 👨", "Male"),
          const SizedBox(height: 16),
          _buildGenderTile("Mwanamke (Woman) 👩", "Female"),
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
            Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: isSelected ? _themeColor : AppColors.textPrimary)),
            if (isSelected) Icon(Icons.check_circle_rounded, color: _themeColor, size: 26),
          ],
        ),
      ),
    );
  }

  Widget _buildAddPhotoStep() {
    return _buildStepLayout(
      title: "Picha Yako Kuu 📸",
      subtitle: "Weka picha inayokuonyesha vizuri sura yako. Picha zenye muonekano mzuri huongeza nafasi ya kupata likes kwa zaidi ya 80%.",
      child: Center(
        child: GestureDetector(
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
                ? ClipRRect(borderRadius: BorderRadius.circular(28), child: Image.file(_profileImage!, fit: BoxFit.cover))
                : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: _themeColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Icon(Icons.add_a_photo_rounded, size: 48, color: _themeColor),
                ),
                const SizedBox(height: 16),
                Text("Gusa Kuweka Picha", style: TextStyle(color: _themeColor, fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDescribeYourselfStep() {
    return _buildStepLayout(
      title: "Jieleze Kidogo (Bio) 📝",
      subtitle: "Andika vitu vichache vinavyokuelezea, kama vile mambo unayopenda kufanya, kazi, au aina ya maisha unayopendelea.",
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
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: _themeColor, width: 2)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          ),
        ),
      ),
    );
  }

  Widget _buildInterestedGenderStep() {
    return _buildStepLayout(
      title: "Unavutiwa na Nani? ❤️",
      subtitle: "Chagua kundi la watu unalotaka lionekane kwenye zoezi lako la ku-swipe na kutafuta marafiki.",
      child: Column(
        children: [
          _buildSelectableOption("Wanaume (Men) 👨", _interestedGender, (val) => setState(() => _interestedGender = val)),
          const SizedBox(height: 14),
          _buildSelectableOption("Wanawake (Women) 👩", _interestedGender, (val) => setState(() => _interestedGender = val)),
          const SizedBox(height: 14),
          _buildSelectableOption("Wote (Everyone) 🌈", _interestedGender, (val) => setState(() => _interestedGender = val)),
        ],
      ),
    );
  }

  Widget _buildRelationshipGoalStep() {
    return _buildStepLayout(
      title: "Unatafuta Nini Hapa? 🎯",
      subtitle: "Weka wazi dhumuni lako ili ulinganishwe na watu wenye nia na malengo yanayofanana na yako kikamilifu.",
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
      title: "Ruhusa Muhimu 🔔",
      subtitle: "Ruhusu huduma hizi ili tuweze kukuonyesha watu walio karibu na eneo lako na kukujulisha pindi unapopata match mpya.",
      child: Column(
        children: [
          _buildPermissionSwitch(
            title: "Location Access (Eneo)",
            subtitle: "Inasaidie kupata na kuonyesha watu waliopo karibu nawe kijiografia.",
            icon: Icons.location_on_rounded,
            value: _locationGranted,
            onChanged: (val) => setState(() => _locationGranted = val),
          ),
          const SizedBox(height: 16),
          _buildPermissionSwitch(
            title: "Notifications (Taarifa)",
            subtitle: "Kupokea ujumbe wa papo hapo na taarifa za likes kutoka kwa wengine.",
            icon: Icons.notifications_active_rounded,
            value: _notificationGranted,
            onChanged: (val) => setState(() => _notificationGranted = val),
          ),
        ],
      ),
    );
  }

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
                  BoxShadow(color: _themeColor.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 10)),
                ],
              ),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(width: 100, height: 100, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: _profileImage != null ? ClipRRect(borderRadius: BorderRadius.circular(50), child: Image.file(_profileImage!, fit: BoxFit.cover)) : Icon(Icons.person, size: 60, color: _themeColor)),
                      Positioned(bottom: 0, right: 0, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle), child: const Icon(Icons.check, color: Colors.white, size: 20))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text("Karibu Sana, ${_nameController.text.isNotEmpty ? _nameController.text : 'Mgeni'}! 🎉", textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(height: 8),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)), child: const Text("Profile Yako Iko Tayari 100%", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
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
                  Row(children: [Icon(Icons.stars_rounded, color: _themeColor, size: 28), const SizedBox(width: 10), const Text("Muhtasari wa Profile", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary))]),
                  const Divider(height: 24),
                  _buildSummaryRow(Icons.cake_rounded, "Umri", "$_calculatedAge Miaka"),
                  _buildSummaryRow(Icons.wc_rounded, "Unatafuta", _interestedGender ?? "Haijachaguliwa"),
                  _buildSummaryRow(Icons.favorite_rounded, "Lengo", _relationshipGoal ?? "Haijachaguliwa"),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text("Bonyeza 'Continue' hapo chini kuweka password yako ya mwisho, kisha uanze kuona watu wanaokuzunguka na kuanza safari yako ya mahusiano! 🔥", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.5, fontWeight: FontWeight.w500)),
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
            BoxShadow(color: isSelected ? _themeColor.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 5)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: isSelected ? _themeColor : AppColors.textPrimary)),
            if (isSelected) Icon(Icons.check_circle_rounded, color: _themeColor, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionSwitch({required String title, required String subtitle, required IconData icon, required bool value, required Function(bool) onChanged}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _buildBoxDecoration(),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: _themeColor.withValues(alpha: 0.12), shape: BoxShape.circle), child: Icon(icon, color: _themeColor, size: 28)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 4), Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3))])),
          Switch(
            value: value,
            activeThumbColor: _themeColor,
            onChanged: (val) async {
              if (val) {
                if (title.contains("Location")) {
                  PermissionStatus status = await Permission.location.request();
                  if (status.isGranted) {
                    onChanged(true);
                  } else if (status.isPermanentlyDenied) {
                    openAppSettings();
                  }
                } else if (title.contains("Notifications")) {
                  PermissionStatus status = await Permission.notification.request();
                  if (status.isGranted) onChanged(true);
                }
              } else {
                onChanged(false);
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
          Text("$title: ", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  BoxDecoration _buildBoxDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 15, offset: const Offset(0, 5)),
      ],
    );
  }
}
