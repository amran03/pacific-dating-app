import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:pacific_dating_app/core/constants/app_color.dart';
import 'package:pacific_dating_app/core/constants/app_radius.dart';
import 'package:pacific_dating_app/core/services/profile_photo_service.dart';

/// Gridi ya picha za profile kwa ajili ya KUHARIRI (max 6).
///
///  - Nafasi 6; tupu zinaonyesha "+" (kupakia picha mpya).
///  - Kugusa picha: chaguo za "Badilisha" na "Futa" (kwa bottom sheet).
///  - Reorder: vitufe vya kushoto/ulia (swap position, batch update).
///  - Picha ya position 0 imewekwa alama "Main" (ni picha ya mbele).
///  - Zuia kufuta picha ya mwisho kama hakuna nyingine.
class ProfilePhotoGrid extends StatelessWidget {
  final List<ProfilePhoto> photos;
  final VoidCallback onAdd;
  final ValueChanged<int> onChange;
  final ValueChanged<int> onDelete;
  final void Function(int oldIndex, int newIndex) onReorder;
  final bool busy;

  const ProfilePhotoGrid({
    super.key,
    required this.photos,
    required this.onAdd,
    required this.onChange,
    required this.onDelete,
    required this.onReorder,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final total = photos.length;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.78,
      ),
      itemCount: ProfilePhotoService.maxPhotos,
      itemBuilder: (context, index) {
        final hasPhoto = index < total;
        if (!hasPhoto) return _emptySlot();
        return _photoSlot(context, index, photos[index], total);
      },
    );
  }

  Widget _emptySlot() {
    return GestureDetector(
      onTap: onAdd,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: AppRadius.md,
          border: Border.all(color: Colors.grey.shade300, width: 1.5),
        ),
        child: const Center(
          child: Icon(Icons.add_a_photo_rounded,
              color: AppColors.primary, size: 28),
        ),
      ),
    );
  }
  Widget _photoSlot(
      BuildContext context, int index, ProfilePhoto photo, int total) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: busy ? null : () => _showOptions(context, index, total),
          child: ClipRRect(
            borderRadius: AppRadius.md,
            child: CachedNetworkImage(
              imageUrl: photo.url,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: Colors.black12),
              errorWidget: (_, __, ___) => Container(
                color: AppColors.inputFill,
                child: const Icon(Icons.broken_image_rounded,
                    color: AppColors.textSecondary),
              ),
            ),
          ),
        ),
        if (index == 0)
          Positioned(
            top: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: AppRadius.sm,
              ),
              child: const Text('Main',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        Positioned(
          bottom: 4,
          left: 2,
          right: 2,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _reorderBtn(Icons.arrow_back_ios_rounded,
                  enabled: !busy && index > 0,
                  onTap: () => onReorder(index, index - 1)),
              _reorderBtn(Icons.arrow_forward_ios_rounded,
                  enabled: !busy && index < total - 1,
                  onTap: () => onReorder(index, index + 1)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reorderBtn(IconData icon,
      {required bool enabled, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: enabled ? 0.45 : 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            size: 14,
            color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.5)),
      ),
    );
  }

  Future<void> _showOptions(BuildContext context, int index, int total) async {
    final isLast = total <= 1;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    const Icon(Icons.swap_horiz_rounded, color: AppColors.primary),
                title: const Text('Badilisha picha'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  onChange(index);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded,
                    color: isLast ? Colors.grey : AppColors.error),
                title: Text(
                    isLast ? 'Futa (zuiliwa — picha ya mwisho)' : 'Futa picha'),
                onTap: isLast
                    ? null
                    : () {
                        Navigator.pop(sheetCtx);
                        onDelete(index);
                      },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
