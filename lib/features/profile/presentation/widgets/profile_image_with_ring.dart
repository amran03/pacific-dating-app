import 'dart:math';

import 'package:flutter/material.dart';

/// Profile image yenye ring ya VIP badge — sasa ni IMPRESSIVE zaidi:
///  - ring ni SweepGradient inayozunguka taratibu (animated rotation)
///  - glow yenye pulse nyepesi kulingana na tier
///  - API ile ile ya awali: imageUrl, badgeTier, size
class ProfileImageWithRing extends StatefulWidget {
  final String? imageUrl;
  final String badgeTier;
  final double size;

  const ProfileImageWithRing({
    super.key,
    required this.imageUrl,
    required this.badgeTier,
    this.size = 100,
  });

  @override
  State<ProfileImageWithRing> createState() => _ProfileImageWithRingState();
}

class _ProfileImageWithRingState extends State<ProfileImageWithRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    // Diamond inazunguka haraka kidogo (inastahili kuonekana!), bronze taratibu.
    final int durationMs = widget.badgeTier.toLowerCase() == 'diamond'
        ? 3000
        : widget.badgeTier.toLowerCase() == 'gold'
            ? 4200
            : 5600;

    _rotationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    );

    if (widget.badgeTier.toLowerCase() != 'none') {
      _rotationController.repeat();
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  List<Color> _tierGradient() {
    switch (widget.badgeTier.toLowerCase()) {
      case 'bronze':
        return const [Color(0xFFB87333), Color(0xFFE8A857), Color(0xFFB87333)];
      case 'gold':
        return const [Color(0xFFFFD700), Color(0xFFFF8C00), Color(0xFFFFD700)];
      case 'diamond':
        return const [Color(0xFFB9F2FF), Color(0xFF71C2FF), Color(0xFFB9F2FF)];
      default:
        return const [];
    }
  }

  bool get _hasValidImage {
    return widget.imageUrl != null && widget.imageUrl!.trim().isNotEmpty;
  }

  Widget _buildFallbackAvatar() {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF252525),
      ),
      child: Icon(
        Icons.person_rounded,
        size: widget.size * 0.48,
        color: Colors.white54,
      ),
    );
  }

  Widget _buildProfileImage({double? explicitSize}) {
    final double imgSize = explicitSize ?? widget.size;

    if (!_hasValidImage) {
      return SizedBox(
        width: imgSize,
        height: imgSize,
        child: _buildFallbackAvatar(),
      );
    }

    return ClipOval(
      child: Image.network(
        widget.imageUrl!.trim(),
        width: imgSize,
        height: imgSize,
        fit: BoxFit.cover,

        // Prevent broken image URLs from crashing the UI.
        errorBuilder: (context, error, stackTrace) {
          return SizedBox(
            width: imgSize,
            height: imgSize,
            child: _buildFallbackAvatar(),
          );
        },

        // Lightweight loading placeholder.
        loadingBuilder: (
          context,
          child,
          loadingProgress,
        ) {
          if (loadingProgress == null) {
            return child;
          }

          return Container(
            width: imgSize,
            height: imgSize,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF252525),
            ),
            child: Center(
              child: SizedBox(
                width: imgSize * 0.22,
                height: imgSize * 0.22,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white54,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Color> tierGradient = _tierGradient();
    final bool hasBadge =
        widget.badgeTier.toLowerCase() != 'none' && tierGradient.isNotEmpty;

    // No badge: show normal circular profile image (same as before).
    if (!hasBadge) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: _buildProfileImage(),
      );
    }

    // Badge: rotating SweepGradient ring + subtle glow pulse.
    final double ringThickness = (widget.size * 0.055).clamp(3.5, 6.0);
    final double gapThickness = (widget.size * 0.03).clamp(2.0, 3.5);
    final double innerSize = widget.size -
        (ringThickness * 2) -
        (gapThickness * 2);

    return AnimatedBuilder(
      animation: _rotationController,
      builder: (context, _) {
        // Glow pulse inafuata rotation — inaonekana hai (alive).
        final double pulse =
            0.30 + 0.18 * (0.5 + 0.5 * sin(_rotationController.value * 2 * pi));

        return Container(
          width: widget.size,
          height: widget.size,
          padding: EdgeInsets.all(ringThickness),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: tierGradient,
              transform: GradientRotation(
                _rotationController.value * 2 * pi,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: tierGradient.first.withOpacity(pulse),
                blurRadius: 12,
                spreadRadius: 1.5,
              ),
            ],
          ),
          child: Container(
            padding: EdgeInsets.all(gapThickness),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: SizedBox(
              width: innerSize,
              height: innerSize,
              child: _buildProfileImage(explicitSize: innerSize),
            ),
          ),
        );
      },
    );
  }
}