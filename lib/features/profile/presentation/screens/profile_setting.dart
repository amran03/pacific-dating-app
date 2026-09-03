import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../core/constants/app_color.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _bioController = TextEditingController();
  final _locationController = TextEditingController();
  final _heightController = TextEditingController();
  final _occupationController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  String _photoUrl = '';

  String? _selectedGender;
  String? _interestedGender;
  String? _relationshipGoal;
  String? _education;
  String? _smokingHabit;
  String? _drinkingHabit;
  final List<String> _selectedInterests = [];
  int _chatUnlockPrice = 0;

  // Sawa kabisa na chaguo zilizotumika kwenye SetupAccountScreen (usajili
  // wa mwanzo), ili data isigongane.
  static const List<String> _interestedGenderOptions = [
    "Wanaume (Men) 👨",
    "Wanawake (Women) 👩",
    "Wote (Everyone) 🌈",
  ];

  List<String> get _relationshipGoals {
    if (_selectedGender == "Female") {
      return [
        "Boyfriend 🕺",
        "Husband 💍",
        "Casual Dating 🥂",
        "Serious Relationship ❤️",
        "New Friends 🤝",
        "Not Sure Yet 🤔",
      ];
    }
    return [
      "Girlfriend 💃",
      "Wife 💍",
      "Casual Dating 🥂",
      "Serious Relationship ❤️",
      "New Friends 🤝",
      "Not Sure Yet 🤔",
    ];
  }

  static const List<String> _educationOptions = [
    "Sekondari",
    "Cheti / Diploma",
    "Shahada (Bachelor's)",
    "Shahada ya Uzamili (Master's)",
    "PhD",
  ];

  static const List<String> _habitOptionsSmoking = ["Sivuti kabisa", "Mara chache", "Mvutaji wa kawaida"];
  static const List<String> _habitOptionsDrinking = ["Sinywi kabisa", "Kijamii tu", "Mara kwa mara"];

  static const List<String> _allInterests = [
    'Photography', 'Music', 'Travel', 'Coffee', 'Cooking', 'Fitness',
    'Movies', 'Gaming', 'Art', 'Reading', 'Dancing', 'Hiking',
    'Football', 'Fashion', 'Business', 'Comedy',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    _heightController.dispose();
    _occupationController.dispose();
    super.dispose();
  }

  // 1. Kusoma taarifa zilizopo kwenye Firestore
  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          _nameController.text = data['name'] ?? '';
          _ageController.text = data['age']?.toString() ?? '';
          _bioController.text = data['bio'] ?? '';
          _locationController.text = data['location'] ?? '';
          _heightController.text = data['heightCm']?.toString() ?? '';
          _occupationController.text = data['occupation'] ?? '';
          _photoUrl = data['profileImageUrl'] ?? '';
          _selectedGender = data['gender'];
          _interestedGender = data['interestedGender'];
          _relationshipGoal = data['relationshipGoal'];
          _education = data['education'];
          _smokingHabit = data['smokingHabit'];
          _drinkingHabit = data['drinkingHabit'];
          _chatUnlockPrice = data['chatUnlockPrice'] ?? 0;
          if (data['interests'] != null) {
            _selectedInterests.addAll(List<String>.from(data['interests']));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Imeshindikana kupakua taarifa: $e")),
          );
        }
      }
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Kubadili Picha ya Profile
  Future<void> _changePhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ImagePicker picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    setState(() => _isUploadingPhoto = true);

    try {
      final ref = FirebaseStorage.instance.ref().child('profile_images').child('${user.uid}.jpg');
      await ref.putFile(File(picked.path));
      final String downloadUrl = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'profileImageUrl': downloadUrl,
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() => _photoUrl = downloadUrl);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Picha imebadilishwa! 📸"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Imeshindikana kupakia picha: $e")));
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  // 2. Kuhifadhi au kubadilisha taarifa kwenye Firestore
  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': _nameController.text.trim(),
        'nameLower': _nameController.text.trim().toLowerCase(),
        'age': int.tryParse(_ageController.text.trim()) ?? 0,
        'bio': _bioController.text.trim(),
        'location': _locationController.text.trim(),
        'heightCm': int.tryParse(_heightController.text.trim()),
        'occupation': _occupationController.text.trim(),
        'gender': _selectedGender,
        'interestedGender': _interestedGender,
        'relationshipGoal': _relationshipGoal,
        'education': _education,
        'smokingHabit': _smokingHabit,
        'drinkingHabit': _drinkingHabit,
        'interests': _selectedInterests,
        'chatUnlockPrice': _chatUnlockPrice,
        'isProfileComplete': true, // Inaiarifu AuthGate kuwa mtumiaji amekamilisha taarifa
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Taarifa zimebadilishwa na kuhifadhiwa kikamilifu! ✅"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Kuna tatizo limetokea wakati wa kuhifadhi: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Edit Profile Settings",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Picha ya Profaili na kitufe cha kubadili
            Center(
              child: GestureDetector(
                onTap: _isUploadingPhoto ? null : _changePhoto,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: NetworkImage(
                        _photoUrl.isNotEmpty
                            ? _photoUrl
                            : 'https://images.unsplash.com/photo-1633332755192-727a05c4013d?q=80&w=300&auto=format&fit=crop',
                      ),
                    ),
                    if (_isUploadingPhoto)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.4),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ==================== TAARIFA ZA MSINGI ====================
            _sectionTitle("Taarifa za Msingi"),
            _buildTextField("Jina Lako (Name)", _nameController),
            const SizedBox(height: 16),
            _buildTextField("Umri (Age)", _ageController, keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            _buildTextField("Eneo Lako (Location)", _locationController),
            const SizedBox(height: 16),
            _buildTextField("Bio / Maelezo Mafupi", _bioController, maxLines: 3),
            const SizedBox(height: 16),
            _buildTextField("Urefu (Height cm)", _heightController, keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            _buildTextField("Kazi/Ajira (Occupation)", _occupationController),
            const SizedBox(height: 24),

            // ==================== JINSIA & MALENGO ====================
            _sectionTitle("Jinsia na Malengo"),
            const Text("Mimi ni", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildChoiceTile("Mwanaume (Man) 👨", _selectedGender == "Male", () {
                    setState(() {
                      _selectedGender = "Male";
                      _relationshipGoal = null; // malengo yanabadilika kutegemea jinsia
                    });
                  }),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildChoiceTile("Mwanamke (Woman) 👩", _selectedGender == "Female", () {
                    setState(() {
                      _selectedGender = "Female";
                      _relationshipGoal = null;
                    });
                  }),
                ),
              ],
            ),
            const SizedBox(height: 16),

            const Align(
              alignment: Alignment.centerLeft,
              child: Text("Ninatafuta", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _interestedGenderOptions
                  .map((opt) => _buildChoiceChip(opt, _interestedGender == opt, () => setState(() => _interestedGender = opt)))
                  .toList(),
            ),
            const SizedBox(height: 16),

            const Align(
              alignment: Alignment.centerLeft,
              child: Text("Lengo la Uhusiano", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _relationshipGoals
                  .map((goal) => _buildChoiceChip(goal, _relationshipGoal == goal, () => setState(() => _relationshipGoal = goal)))
                  .toList(),
            ),
            const SizedBox(height: 24),

            // ==================== ELIMU & TABIA ====================
            _sectionTitle("Elimu na Tabia"),
            _buildDropdown("Kiwango cha Elimu", _education, _educationOptions, (val) => setState(() => _education = val)),
            const SizedBox(height: 16),
            _buildDropdown("Uvutaji Sigara", _smokingHabit, _habitOptionsSmoking, (val) => setState(() => _smokingHabit = val)),
            const SizedBox(height: 16),
            _buildDropdown("Unywaji Pombe", _drinkingHabit, _habitOptionsDrinking, (val) => setState(() => _drinkingHabit = val)),
            const SizedBox(height: 24),

            // ==================== MAPENDELEO ====================
            _sectionTitle("Mapendeleo (Interests)"),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allInterests.map((interest) {
                final bool isSelected = _selectedInterests.contains(interest);
                return FilterChip(
                  label: Text(interest),
                  selected: isSelected,
                  selectedColor: AppColors.primary.withOpacity(0.15),
                  checkmarkColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? AppColors.primary : Colors.black87,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: isSelected ? AppColors.primary : Colors.grey.shade300),
                  ),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedInterests.add(interest);
                      } else {
                        _selectedInterests.remove(interest);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // ==================== BEI YA KUFUNGUA CHAT ====================
            _sectionTitle("Bei ya Kufungua Chat 🔒"),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Watu wapya wanaotaka kuanza mazungumzo na wewe (kabla ya ku-match) watalipa Coins hizi mara moja tu. Weka 0 kama unataka kuwa BURE kabisa.",
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Bei ya Sasa", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.coinGold.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _chatUnlockPrice == 0 ? "BURE 🆓" : "🪙 $_chatUnlockPrice Coins",
                          style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.coinGold),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _chatUnlockPrice.toDouble(),
                    min: 0,
                    max: 500,
                    divisions: 50,
                    activeColor: AppColors.primary,
                    label: _chatUnlockPrice == 0 ? "Bure" : "$_chatUnlockPrice",
                    onChanged: (val) => setState(() => _chatUnlockPrice = val.round()),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // Kitufe cha Kuhifadhi
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
                    : const Text(
                  "Hifadhi Mabadiliko",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.primary),
        ),
      ),
    );
  }

  Widget _buildChoiceTile(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? AppColors.primary : Colors.grey.shade300),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildChoiceChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? AppColors.primary : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, String? value, List<String> options, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              hint: const Text("Chagua"),
              items: options.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {int maxLines = 1, TextInputType keyboardType = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
          ),
        ),
      ],
    );
  }
}