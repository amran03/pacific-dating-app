import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import 'package:pacific_dating_app/core/services/profile_photo_service.dart';

/// Carousel ya picha za profile ya mtu mwingine (PageView ya picha zote).
///
///  - Inapakia picha kutoka `profile_photos` (zimepangwa kwa position).
///  - Gusa upande wa kulia/kushoto kwenda inayofuata/iliyopita (kama Tinder).
///  - Dots (SmoothPageIndicator) chini/z juu zinaonyesha picha iliyobaki.
///  - Placeholder wakati inapakia; ikoni ya hitilafu ikishindikana.
///  - Ikiwa hakuna picha nyingi, inarudi kwenye [fallbackUrl] (picha ya mbele)
///    au [initials] kama hakuna picha kabisa.
class ProfilePhotoCarousel extends StatefulWidget {
  final String uid;
  final String fallbackUrl;
  final String initials;

  const ProfilePhotoCarousel({
    super.key,
    required this.uid,
    required this.fallbackUrl,
    required this.initials,
  });

  @override
  State<ProfilePhotoCarousel> createState() => _ProfilePhotoCarouselState();
}

class _ProfilePhotoCarouselState extends State<ProfilePhotoCarousel> {
  final _service = ProfilePhotoService.instance;
  final _controller = PageController();
  List<ProfilePhoto> _photos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final photos = await _service.fetchPhotos(widget.uid);
      // Pakia mapema picha inayofuata (ili slide iwe laini).
      if (!mounted) return;
      for (final p in photos.take(ProfilePhotoService.maxPhotos)) {
        if (p.url.startsWith('http')) {
          precacheImage(CachedNetworkImageProvider(p.url), context);
        }
      }
      setState(() {
        _photos = photos;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Orodha ya URL za kuonyesha.
    final urls = <String>[
      if (_photos.isNotEmpty)
        ..._photos.map((p) => p.url)
      else if (widget.fallbackUrl.isNotEmpty)
        widget.fallbackUrl
    ];

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    if (urls.isEmpty) {
      return _initialsBox();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: urls.length,
          itemBuilder: (context, index) {
            return CachedNetworkImage(
              imageUrl: urls[index],
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: Colors.black12,
                child: const Center(
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                ),
              ),
              errorWidget: (context, url, error) => _initialsBox(),
            );
          },
        ),
        // Dots — zinaonyesha picha iliyobaki (Tinder-style).
        if (urls.length > 1)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: SmoothPageIndicator(
                controller: _controller,
                count: urls.length,
                effect: const ExpandingDotsEffect(
                  dotHeight: 6,
                  dotWidth: 6,
                  expansionFactor: 3,
                  spacing: 6,
                  activeDotColor: Colors.white,
                  dotColor: Colors.white54,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _initialsBox() {
    return Container(
      color: const Color(0xFF2A2F3A),
      alignment: Alignment.center,
      child: Text(
        widget.initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 64,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
