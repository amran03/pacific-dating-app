import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/storage_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final SupabaseClient _client = Supabase.instance.client;
  final StorageService _storage = StorageService();
  final ImagePicker _picker = ImagePicker();

  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _jobController;
  late final TextEditingController _locationController;

  bool _isLoading = true;
  bool _isUploadingPhoto = false;
  bool _isSaving = false;
  String? _profileImageUrl;
  final List<String> _selectedInterests = [];
  static const List<String> _allInterests = [
    'Photography', 'Music', 'Travel', 'Coffee', 'Cooking', 'Fitness',
    'Movies', 'Gaming', 'Art', 'Reading', 'Dancing', 'Hiking',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _bioController = TextEditingController();
    _jobController = TextEditingController();
    _locationController = TextEditingController();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final data =
          await _client.from('users').select().eq('uid', user.id).maybeSingle();
      if (data != null && mounted) {
        setState(() {
          _nameController.text = (data['name'] ?? '') as String;
          _bioController.text = (data['bio'] ?? '') as String;
          _jobController.text = (data['occupation'] ?? '') as String;
          _locationController.text = (data['location'] ?? '') as String;
          _profileImageUrl = data['profile_image_url'] as String?;
          if (data['interests'] is List) {
            _selectedInterests.addAll(
              (data['interests'] as List).whereType<String>(),
            );
          }
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Load profile failed: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Real photo upload to Supabase Storage (avatars bucket) + DB update.
  Future<void> _changePhoto() async {
    final user = _client.auth.currentUser;
    if (user == null || _isUploadingPhoto) return;

    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final url = await _storage.uploadProfileImage(user.id, File(picked.path));
      if (url == null) throw Exception('Upload failed');

      await _client
          .from('users')
          .update({'profile_image_url': url}).eq('uid', user.id);

      if (mounted) {
        setState(() => _profileImageUrl = url);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Picha ya profile imebadilishwa!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imeshindikana kupakia picha: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final user = _client.auth.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);
    try {
      await _client.from('users').update({
        'name': _nameController.text.trim(),
        'name_lower': _nameController.text.trim().toLowerCase(),
        'bio': _bioController.text.trim(),
        'occupation': _jobController.text.trim(),
        'location': _locationController.text.trim(),
        'interests': _selectedInterests,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('uid', user.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imeshindikana kuhifadhi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _jobController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1A1A1A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveProfile,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      color: Color(0xFFFF4B72),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF4B72)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPhotoHeader(),
                    const SizedBox(height: 28),
                    _buildTextField(_nameController, 'Name', 'Jina lako'),
                    const SizedBox(height: 16),
                    _buildTextField(_bioController, 'Bio',
                        'Andika maelezo mafupi...', maxLines: 4),
                    const SizedBox(height: 16),
                    _buildTextField(_jobController, 'Occupation', 'Kazi yako'),
                    const SizedBox(height: 16),
                    _buildTextField(_locationController, 'Location', 'Mji, Nchi'),
                    const SizedBox(height: 24),
                    const Text(
                      'Interests',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _allInterests.map((interest) {
                        final bool selected =
                            _selectedInterests.contains(interest);
                        return FilterChip(
                          label: Text(interest),
                          selected: selected,
                          selectedColor:
                              const Color(0xFFFF4B72).withValues(alpha: 0.2),
                          checkmarkColor: const Color(0xFFFF4B72),
                          onSelected: (val) {
                            setState(() {
                              val
                                  ? _selectedInterests.add(interest)
                                  : _selectedInterests.remove(interest);
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF4B72),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        child: const Text(
                          'Save Changes',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
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

  Widget _buildPhotoHeader() {
    return Center(
      child: GestureDetector(
        onTap: _isUploadingPhoto ? null : _changePhoto,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF4B72).withValues(alpha: 0.12),
                border: Border.all(color: const Color(0xFFFF4B72), width: 2),
              ),
              child: _profileImageUrl != null && _profileImageUrl!.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        _profileImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _initialAvatar(),
                      ),
                    )
                  : _initialAvatar(),
            ),
            if (_isUploadingPhoto)
              Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black38,
                ),
                child: const CircularProgressIndicator(color: Colors.white),
              )
            else
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF4B72),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _initialAvatar() {
    final String name = _nameController.text;
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 44,
          fontWeight: FontWeight.w900,
          color: Color(0xFFFF4B72),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String hint, {
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: (value) => (value == null || value.trim().isEmpty)
              ? 'Tafadhali jaza $label'
              : null,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF5F5F7),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
