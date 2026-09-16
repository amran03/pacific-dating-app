import 'package:flutter/material.dart';

/// Loading animation ya kisasa: MOYO UNAODUNDA (heartbeat).
///
/// Moyo unapiga to rhythm halisi ya moyo ("lub-dub"): mi_kubwa mbili ya
/// haraka ikifuatiwa na mapumziko — inafanya loading kuwa hai na ya kipekee
/// badala ya spinner ya kawaida.
class HeartLoader extends StatefulWidget {
  final double size;
  final Color color;

  const HeartLoader({
    super.key,
    this.size = 56,
    this.color = const Color(0xFFFF4B72),
  });

  @override
  State<HeartLoader> createState() => _HeartLoaderState();
}

class _HeartLoaderState extends State<HeartLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Rhythm ya moyo: lub (0.00-0.12) -> dub (0.18-0.30) -> pumziko (0.30-1.0)
  static final Animatable<double> _beatCurve = CurveTween(
    curve: const Cubic(0.2, 0.0, 0.4, 1.0),
  );

  double _beatScale(double t) {
    double beat = 0.0;
    // Lub
    if (t < 0.12) {
      beat = _beatCurve.transform(t / 0.12);
    }
    // Dub (pili, kidogo njiani)
    else if (t >= 0.18 && t < 0.30) {
      beat = _beatCurve.transform((t - 0.18) / 0.12) * 0.75;
    }
    // Pumziko — moyo unarudi to ukubwa wake
    else if (t >= 0.30) {
      beat = 0.0;
    }
    return 1.0 + beat * 0.22;
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          final scale = _beatScale(t);
          // Glow inapaka pamoja na kipigo
          final glow = (t < 0.30 ? 0.35 : 0.12) + 0.1;

          return Transform.scale(
            scale: scale,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: glow),
                    blurRadius: widget.size * 0.45,
                    spreadRadius: widget.size * 0.06,
                  ),
                ],
              ),
              child: child,
            ),
          );
        },
        child: Icon(
          Icons.favorite_rounded,
          color: widget.color,
          size: widget.size * 0.82,
        ),
      ),
    );
  }
}
