import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_color.dart';
import '../../../../core/widgets/heart_loader.dart';
import '../../../dashboard/presentation/screens/main_dashboard_screen.dart';

class PhotoUploadScreen extends StatefulWidget {
  final String firstName;
  final DateTime birthDate;
  final String gender;

  const PhotoUploadScreen({
    super.key,
    required this.firstName,
    required this.birthDate,
    required this.gender,
  });

  @override
  State<PhotoUploadScreen> createState() => _PhotoUploadScreenState();
}

class _PhotoUploadScreenState extends State<PhotoUploadScreen> {
  // Tutatumia list hii kufuatilia picha (kwa sasa ni placeholder)
  final List<String?> _photos = List.generate(6, (_) => null);
  bool _isSaving = false;

  int _computedAge() {
    final now = DateTime.now();
    int age = now.year - widget.birthDate.year;
    if (now.month < widget.birthDate.month ||
        (now.month == widget.birthDate.month &&
            now.day < widget.birthDate.day)) {
      age--;
    }
    return age;
  }

  /// Huokoa taarifa zote za onboarding kwenye `users` table na
  /// kuashiria profile imekamilika — hii inamruhusu user kurudi
  /// moja to moja kwenye dashboard anapofungua app tena (AuthGate).
  Future<void> _finishSetup() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) throw Exception('Haujaingia (no session)');

      // Picha ya kwanza iliyowekwa (kama ipo) inakuwa profile image.
      final firstPhoto = _photos.whereType<String>().isNotEmpty
          ? _photos.whereType<String>().first
          : null;

      await Supabase.instance.client.from('users').update({
        'name': widget.firstName,
        'name_lower': widget.firstName.toLowerCase(),
        'birth_date': widget.birthDate.toIso8601String().substring(0, 10),
        'age': _computedAge(),
        'gender': widget.gender,
        if (firstPhoto != null) 'profile_image_url': firstPhoto,
        'is_profile_complete': true,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('uid', uid);

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => const MainDashboardScreen(),
        ),
        (route) => false, // Inafuta skrini za nyuma ili asirudi kwenye Onboarding
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Widget _buildPhotoSlot(int index) {
    bool hasPhoto = _photos[index] != null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasPhoto ? AppColors.primary : Colors.grey.shade300,
          width: 1.5,
        ),
      ),
      child: Stack(
        children: [
          if (!hasPhoto)
            const Center(
              child: Icon(
                Icons.add_a_photo_rounded,
                color: AppColors.textSecondary,
                size: 28,
              ),
            ),
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: hasPhoto ? Colors.red : AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasPhoto ? Icons.close : Icons.add,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Add Your Best Photos",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Add at least 2 photos to build your profile.",
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 30),

              // 6 Grid Photo Slots
              Expanded(
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: 6,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () {
                        // TODO: Weka logic ya kuchagua picha kutoka Gallery/Camera
                      },
                      child: _buildPhotoSlot(index),
                    );
                  },
                ),
              ),

              // Finish Setup Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _finishSetup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: _isSaving
                      ? const HeartLoader(size: 26, color: Colors.white)
                      : const Text(
                    "Finish Setup",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}