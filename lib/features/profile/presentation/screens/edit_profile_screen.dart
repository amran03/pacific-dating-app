
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:pacific_dating_app/core/services/profile_photo_service.dart';
import 'package:pacific_dating_app/core/widgets/heart_loader.dart';
import 'package:pacific_dating_app/core/widgets/app_notification_overlay.dart';
import 'package:pacific_dating_app/core/constants/app_radius.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final SupabaseClient _client = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  late final TextEditingController _jobController;
  late final TextEditingController _locationController;

  // Jina la kuonyeshwa na @username ya awali — kwa kikomo cha kubadilisha
  // mara moja kwa mwezi (30 siku). ISO timestamps kutoka DB.
  String _originalName = '';
  String _originalUsername = '';
  String? _nameChangedAt;
  String? _usernameChangedAt;

  bool _isLoading = true;
  bool _isUploadingPhoto = false;
  bool _isSaving = false;
  // Picha za profile (max 6) Ã¢â‚¬â€ zinaonyeshwa kwenye grid ya kuhariri.
  List<ProfilePhoto> _photos = [];
  bool _photosLoading = true;
  final ProfilePhotoService _photoService = ProfilePhotoService.instance;
  final List<String> _selectedInterests = [];
  static const List<String> _allInterests = [
    'Photography', 'Music', 'Travel', 'Coffee', 'Cooking', 'Fitness',
    'Movies', 'Gaming', 'Art', 'Reading', 'Dancing', 'Hiking',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _usernameController = TextEditingController();
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
          _usernameController.text = (data['username'] ?? '') as String;
          _bioController.text = (data['bio'] ?? '') as String;
          _jobController.text = (data['occupation'] ?? '') as String;
          _locationController.text = (data['location'] ?? '') as String;
          _originalName = _nameController.text.trim();
          _originalUsername = _usernameController.text.trim();
          _nameChangedAt = data['name_changed_at']?.toString();
          _usernameChangedAt = data['username_changed_at']?.toString();
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
    // Pakia picha za profile (kando na profile) Ã¢â‚¬â€ grid ya 6.
    await _loadPhotos();
  }

  /// Pakia picha zote za profile kutoka `profile_photos`.
  Future<void> _loadPhotos() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _photosLoading = false);
      return;
    }
    try {
      final photos = await _photoService.fetchPhotos(user.id);
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _photosLoading = false;
      });
    } catch (e) {
      debugPrint('Load photos failed: $e');
      if (mounted) setState(() => _photosLoading = false);
    }
  }

  /// Kikomo: ni picha ngapi zimebaki (6 - zilizopo).
  int get _remaining => ProfilePhotoService.maxPhotos - _photos.length;

  /// Chagua na uweke picha mpya (multi). Akizidisha kikomo, onyesha ujumbe.
  Future<void> _addPhotos() async {
    final user = _client.auth.currentUser;
    if (user == null || _isUploadingPhoto) return;

    if (_remaining <= 0) {
      showAppNotification(
        context,
        'Unaweza kuweka picha ${ProfilePhotoService.maxPhotos} tu.',
        type: AppNotificationType.warning,
      );
      return;
    }

    final picked = await _photoService.pickMultiImage(remaining: _remaining);
    if (picked.isEmpty) return;

    if (picked.length > _remaining) {
      if (!mounted) return;
      showAppNotification(
        context,
        'Unaweza kuweka picha ${ProfilePhotoService.maxPhotos} tu.',
        type: AppNotificationType.warning,
      );
    }

    setState(() => _isUploadingPhoto = true);

    int ok = 0;
    String? errMsg;
    bool errNetwork = false;
    for (final file in picked.take(_remaining)) {
      try {
        final photo = await _photoService.uploadOne(user.id, file);
        if (photo != null) ok++;
      } on ProfilePhotoException catch (e) {
        // Simama kwenye hitilafu ya kwanza (mtandao/ruhusa/kikomo) —
        // onyesha ujumbe halisi, si "imeshindikana" tupu.
        errMsg = e.message;
        errNetwork = e.isNetwork;
        break;
      }
    }

    if (!mounted) return;
    setState(() => _isUploadingPhoto = false);
    await _loadPhotos();

    if (!mounted) return;
    if (ok > 0) {
      showAppNotification(
        context,
        'Picha $ok zimeongezwa.',
        type: AppNotificationType.success,
      );
    } else {
      showAppNotification(
        context,
        errMsg ?? 'Imeshindikana kupakia picha.',
        type: AppNotificationType.error,
        title: errNetwork ? 'Hakuna mtandao' : null,
      );
    }
  }

  /// Badilisha picha kwenye slot fulani (futa ya zamani, weka mpya).
  Future<void> _changePhotoAt(int index) async {
    final user = _client.auth.currentUser;
    if (user == null || _isUploadingPhoto) return;
    if (index >= _photos.length) return;

    final old = _photos[index];
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _isUploadingPhoto = true);
    // Weka picha mpya kwa position ile ile.
    ProfilePhoto? created;
    String? errMsg;
    bool errNetwork = false;
    try {
      created =
          await _photoService.uploadOne(user.id, picked, position: old.position);
    } on ProfilePhotoException catch (e) {
      errMsg = e.message;
      errNetwork = e.isNetwork;
    }
    if (created != null) {
      // Futa ya zamani (storage + row) Ã¢â‚¬â€ position imehifadhiwa.
      await _photoService.deletePhoto(old);
    }
    if (!mounted) return;
    setState(() => _isUploadingPhoto = false);
    await _loadPhotos();
    if (!mounted) return;
    if (created != null) {
      showAppNotification(
        context,
        'Picha imebadilishwa.',
        type: AppNotificationType.success,
      );
    } else {
      showAppNotification(
        context,
        errMsg ?? 'Imeshindikana kubadilisha.',
        type: AppNotificationType.error,
        title: errNetwork ? 'Hakuna mtandao' : null,
      );
    }
  }

  /// Futa picha kwenye slot fulani.
  Future<void> _deletePhotoAt(int index) async {
    if (_isUploadingPhoto) return;
    if (index >= _photos.length) return;

    final photo = _photos[index];
    final ok = await _photoService.deletePhoto(photo);
    if (!mounted) return;
    await _loadPhotos();
    if (!mounted) return;
    showAppNotification(
      context,
      ok ? 'Picha imefutwa.' : 'Imeshindikana kufuta.',
      type: ok ? AppNotificationType.success : AppNotificationType.error,
    );
  }

  static const Duration _changeLimit = Duration(days: 30);

  /// True kama bado ndani ya kikomo cha siku 30 tangu marekebisho ya mwisho.
  /// Rekodi ispokuwa (null) => anaruhusiwa kubadilisha sasa.
  bool _withinChangeLimit(String? changedAtIso) {
    final dt = DateTime.tryParse(changedAtIso ?? '');
    if (dt == null) return false;
    return DateTime.now().difference(dt) < _changeLimit;
  }

  /// Siku zilizobaki kabla ya kubadilisha tena (kwa UI hint).
  int _daysRemaining(String? changedAtIso) {
    final dt = DateTime.tryParse(changedAtIso ?? '');
    if (dt == null) return 0;
    final left = _changeLimit - DateTime.now().difference(dt);
    return (left.inDays + 1).clamp(0, 30);
  }

  /// Format ya @username: herufi ndogo, nambari, underscore; urefu 3–20.
  bool _isValidUsername(String u) => RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(u);

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final user = _client.auth.currentUser;
    if (user == null) return;

    final String name = _nameController.text.trim();
    final String username = _usernameController.text.trim().toLowerCase();

    // @username ni LAZIMA na lazima iwe na format sahihi.
    if (username.isEmpty) {
      showAppNotification(context, 'Weka @username (ni lazima).',
          type: AppNotificationType.error);
      return;
    }
    if (!_isValidUsername(username)) {
      showAppNotification(
          context,
          '@username: tumia herufi ndogo, nambari na "_" tu (urefu 3–20).',
          type: AppNotificationType.error);
      return;
    }

    final bool usernameChanged = username != _originalUsername;
    final bool nameChanged = name != _originalName;

    // Kikomo cha kubadilisha MARA MOJA kwa mwezi (30 siku).
    if (usernameChanged && _withinChangeLimit(_usernameChangedAt)) {
      showAppNotification(
          context,
          'Unaweza kubadilisha @username mara moja kwa mwezi. Jaribu tena '
          'baada ya siku ${_daysRemaining(_usernameChangedAt)}.',
          type: AppNotificationType.error);
      return;
    }
    if (nameChanged && _withinChangeLimit(_nameChangedAt)) {
      showAppNotification(
          context,
          'Unaweza kubadilisha jina lako mara moja kwa mwezi. Jaribu tena '
          'baada ya siku ${_daysRemaining(_nameChangedAt)}.',
          type: AppNotificationType.error);
      return;
    }

    setState(() => _isSaving = true);
    try {
      // Kizuizi cha kipekee: hakikisha @username haijachukuliwa na mwingine.
      if (usernameChanged) {
        final taken = await _client
            .from('users')
            .select('uid')
            .eq('username', username)
            .neq('uid', user.id)
            .maybeSingle();
        if (taken != null) {
          if (mounted) {
            showAppNotification(context, '@username "$username" tayari imetumika.',
                type: AppNotificationType.error);
          }
          return;
        }
      }

      final String nowIso = DateTime.now().toIso8601String();
      final Map<String, dynamic> payload = {
        'name': name,
        'name_lower': name.toLowerCase(),
        'username': username,
        'bio': _bioController.text.trim(),
        'occupation': _jobController.text.trim(),
        'location': _locationController.text.trim(),
        'interests': _selectedInterests,
        'updated_at': nowIso,
      };
      if (usernameChanged) payload['username_changed_at'] = nowIso;
      if (nameChanged) payload['name_changed_at'] = nowIso;

      await _client.from('users').update(payload).eq('uid', user.id);

      if (mounted) {
        _originalName = name;
        _originalUsername = username;
        showAppNotification(context, 'Profile updated successfully!',
            color: Colors.green);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        showAppNotification(context, 'Failed to save: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
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
          ? const Center(child: HeartLoader(size: 72))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPhotoHeader(),
                    const SizedBox(height: 28),
                    _buildUsernameField(),
                    const SizedBox(height: 16),
                    _buildNameField(),
                    const SizedBox(height: 16),
                    _buildTextField(_bioController, 'Bio',
                        'Write a short bio...', maxLines: 4, optional: true),
                    const SizedBox(height: 16),
                    _buildTextField(_jobController, 'Occupation', 'Your occupation'),
                    const SizedBox(height: 16),
                    _buildTextField(_locationController, 'Location', 'City, Country'),
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
                            borderRadius: AppRadius.xl,
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
    // Gridi ya picha za profile (max 6) Ã¢â‚¬â€ kuweka, kubadilisha, kufuta na
    // kupanga upya. Picha ya kwanza (position 0) ni picha ya mbele.
    // Sehemu MBILI tofauti:
    //  1) Profile Picture — picha 1 kubwa (position 0), inaonekana kwanza.
    //  2) Additional Pictures — picha 5 ndogo za ziada (position 1–5), mtumiaji
    //     mwengine akitazama wasifu ndizo ataona baada ya picha ya mbele.
    if (_photosLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: HeartLoader(size: 40),
        ),
      );
    }
    final ProfilePhoto? main = _photos.isEmpty ? null : _photos.first;
    final List<ProfilePhoto> extra =
        _photos.length > 1 ? _photos.sublist(1) : <ProfilePhoto>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---- 1) PROFILE PICTURE ----
        const Text(
          'Profile Picture',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Huonekana kwanza kwenye Discover na wasifu wako.',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF5C5C5C)),
        ),
        const SizedBox(height: 12),
        Stack(
          children: [
            _mainPhotoTile(main),
            if (_isUploadingPhoto) _busyOverlay(),
          ],
        ),
        const SizedBox(height: 20),

        // ---- 2) ADDITIONAL PICTURES ----
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Additional Pictures',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A),
              ),
            ),
            Text(
              '${extra.length}/5',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5C5C5C),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Hizi huonekana kwa wengine wakiti wanaangalia wasifu wako. (Hiari)',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF5C5C5C)),
        ),
        const SizedBox(height: 12),
        Stack(
          children: [
            _additionalPhotosWrap(extra),
            if (_isUploadingPhoto) _busyOverlay(),
          ],
        ),
      ],
    );
  }

  static const double _extraTileSize = 104;

  Widget _busyOverlay() => Positioned.fill(
        child: Container(
          alignment: Alignment.center,
          color: Colors.white.withValues(alpha: 0.5),
          child: const HeartLoader(size: 44),
        ),
      );

  // Picha kubwa ya mbele (position 0). Ipo -> gusa = badilisha; hakuna -> weka.
  Widget _mainPhotoTile(ProfilePhoto? photo) {
    final bool has = photo != null;
    return GestureDetector(
      onTap:
          _isUploadingPhoto ? null : (has ? () => _changePhotoAt(0) : _addPhotos),
      child: Container(
        height: 220,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F7),
          borderRadius: AppRadius.card,
          border: Border.all(color: const Color(0xFFE3E4E8), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: has
            ? Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: photo.url,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        const Center(child: HeartLoader(size: 30)),
                    errorWidget: (_, __, ___) => _photoPlaceholder(),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: _roundIconBadge(Icons.camera_alt_outlined),
                  ),
                ],
              )
            : Center(child: _photoPlaceholder(plus: true)),
      ),
    );
  }

  Widget _additionalPhotosWrap(List<ProfilePhoto> extra) {
    final int filled = extra.length;
    final int empty = 5 - filled;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (int i = 0; i < filled; i++)
          _extraPhotoTile(extra[i], globalIndex: i + 1),
        for (int i = 0; i < empty; i++) _addTile(),
      ],
    );
  }

  Widget _extraPhotoTile(ProfilePhoto photo, {required int globalIndex}) {
    return GestureDetector(
      onTap: _isUploadingPhoto ? null : () => _showExtraOptions(globalIndex),
      child: Container(
        width: _extraTileSize,
        height: _extraTileSize,
        decoration: BoxDecoration(
          borderRadius: AppRadius.md,
          border: Border.all(color: const Color(0xFFE3E4E8), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: photo.url,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: const Color(0xFFF5F5F7)),
              errorWidget: (_, __, ___) => _photoPlaceholder(),
            ),
            Positioned(
              right: 6,
              bottom: 6,
              child: _roundIconBadge(Icons.tune_rounded, size: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addTile() {
    return GestureDetector(
      onTap: _isUploadingPhoto ? null : _addPhotos,
      child: Container(
        width: _extraTileSize,
        height: _extraTileSize,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F7),
          borderRadius: AppRadius.md,
          border: Border.all(color: const Color(0xFFE3E4E8), width: 1.5),
        ),
        child: const Icon(Icons.add_a_photo_outlined,
            color: Color(0xFF9AA0A6), size: 26),
      ),
    );
  }

  Widget _roundIconBadge(IconData icon, {double size = 16}) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: size, color: Colors.white),
    );
  }

  Widget _photoPlaceholder({bool plus = false}) {
    return Container(
      color: const Color(0xFFF5F5F7),
      child: Icon(
        plus ? Icons.add_a_photo_outlined : Icons.image_outlined,
        color: const Color(0xFF9AA0A6),
        size: plus ? 40 : 30,
      ),
    );
  }

  Future<void> _showExtraOptions(int index) async {
    final bool isLast = _photos.length <= 1;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.swap_horiz_rounded, color: Color(0xFFFF4B72)),
              title: const Text('Badilisha picha'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _changePhotoAt(index);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: isLast ? Colors.grey : const Color(0xFFD93025)),
              title: Text(
                  isLast ? 'Futa (zuiliwa - picha ya mwisho)' : 'Futa picha'),
              onTap: isLast
                  ? null
                  : () {
                      Navigator.pop(sheetCtx);
                      _deletePhotoAt(index);
                    },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// @username (handle ya kipekee) — ni lazima, format sahihi, kubadilisha
  /// mara moja kwa mwezi. Inaonyesha kikomo ikiwa bado mdakiko.
  Widget _buildUsernameField() {
    final bool locked =
        _withinChangeLimit(_usernameChangedAt) && _originalUsername.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('@username',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextFormField(
          controller: _usernameController,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          validator: (value) {
            final u = (value ?? '').trim();
            if (u.isEmpty) return 'Weka @username (ni lazima)';
            if (!_isValidUsername(u.toLowerCase())) {
              return 'Herufi ndogo, nambari na "_" tu (urefu 3–20)';
            }
            return null;
          },
          decoration: InputDecoration(
            prefixText: '@',
            hintText: 'username_wako',
            filled: true,
            fillColor: const Color(0xFFF5F5F7),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: AppRadius.sm,
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          locked
              ? 'Umebadilisha @username hivi karibuni. Subiri siku '
                  '${_daysRemaining(_usernameChangedAt)} zilizobaki.'
              : 'Lazima iwe unique. Unaweza kubadilisha mara moja kwa mwezi.',
          style: TextStyle(
            fontSize: 12,
            color: locked ? const Color(0xFFE53935) : const Color(0xFF5C5C5C),
          ),
        ),
      ],
    );
  }

  /// Jina la kuonyeshwa (display name) — ni lazima, kubadilisha mara moja
  /// kwa mwezi.
  Widget _buildNameField() {
    final bool locked =
        _withinChangeLimit(_nameChangedAt) && _originalName.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Name',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextFormField(
          controller: _nameController,
          textInputAction: TextInputAction.next,
          validator: (value) => (value == null || value.trim().isEmpty)
              ? 'Jina ni lazima'
              : null,
          decoration: InputDecoration(
            hintText: 'Your name',
            filled: true,
            fillColor: const Color(0xFFF5F5F7),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: AppRadius.sm,
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          locked
              ? 'Umebadilisha jina hivi karibuni. Subiri siku '
                  '${_daysRemaining(_nameChangedAt)} zilizobaki.'
              : 'Unaweza kubadilisha jina mara moja kwa mwezi.',
          style: TextStyle(
            fontSize: 12,
            color: locked ? const Color(0xFFE53935) : const Color(0xFF5C5C5C),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String hint, {
    int maxLines = 1,
    bool optional = false,
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
          validator: (value) =>
              (!optional && (value == null || value.trim().isEmpty))
                  ? 'Please fill in $label'
                  : null,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF5F5F7),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: AppRadius.sm,
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
