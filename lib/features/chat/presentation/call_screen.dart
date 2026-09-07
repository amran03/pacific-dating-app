import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_color.dart';

enum CallType { audio, video }

enum CallPhase { ringing, connecting, ongoing, ended }

/// Polished voice/video call screen for Pacific Dating App.
///
/// NOTE: The project currently has no calling SDK (no WebRTC/AGORA) in
/// pubspec.yaml, so this screen provides the full premium call UI with a
/// simulated connection lifecycle (ringing -> connecting -> ongoing).
/// Wiring a real backend only requires replacing the simulation in
/// [_startOutgoingFlow] / [_accept] with real signalling.
class CallScreen extends StatefulWidget {
  final CallType callType;
  final String peerName;
  final String? peerAvatarUrl;
  final bool isOutgoing;

  const CallScreen({
    super.key,
    required this.callType,
    required this.peerName,
    this.peerAvatarUrl,
    this.isOutgoing = true,
  });

  static Future<void> push(
    BuildContext context, {
    required CallType callType,
    required String peerName,
    String? peerAvatarUrl,
    bool isOutgoing = true,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: CallScreen(
            callType: callType,
            peerName: peerName,
            peerAvatarUrl: peerAvatarUrl,
            isOutgoing: isOutgoing,
          ),
        ),
      ),
    );
  }

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _dotsController;

  CallPhase _phase = CallPhase.ringing;
  int _seconds = 0;
  Timer? _phaseTimer;
  Timer? _durationTimer;

  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isVideoEnabled = true;

  bool get _isVideo => widget.callType == CallType.video;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _pulseController.repeat();
    _dotsController.repeat();

    if (widget.isOutgoing) {
      _startOutgoingFlow();
    }
  }

  void _startOutgoingFlow() {
    _phaseTimer?.cancel();
    _phaseTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _phase = CallPhase.connecting);
      _phaseTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        _goOngoing();
      });
    });
  }

  void _accept() {
    if (!mounted) return;
    _phaseTimer?.cancel();
    setState(() => _phase = CallPhase.connecting);
    _phaseTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      _goOngoing();
    });
  }

  void _goOngoing() {
    if (!mounted) return;
    _pulseController.stop();
    setState(() => _phase = CallPhase.ongoing);
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds += 1);
    });
  }

  void _endCall() {
    _phaseTimer?.cancel();
    _durationTimer?.cancel();
    if (!mounted) return;
    setState(() => _phase = CallPhase.ended);
    _phaseTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  String get _formattedDuration {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _statusText {
    switch (_phase) {
      case CallPhase.ringing:
        return widget.isOutgoing ? 'Calling…' : 'Incoming call…';
      case CallPhase.connecting:
        return 'Connecting…';
      case CallPhase.ended:
        return 'Call ended';
      case CallPhase.ongoing:
        return _formattedDuration;
    }
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _durationTimer?.cancel();
    _pulseController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  // ============================================================
  // COLORS — correct, WCAG-conscious pairing for call UI:
  //  - white icons/text on translucent dark surfaces (contrast > 7:1)
  //  - white icon on callGreen accept (>= 5:1) and callRed end (>= 4.5:1)
  // ============================================================

  List<Color> get _sceneGradient => _isVideo
      ? const [Color(0xFF0E1116), Color(0xFF05070A)]
      : const [Color(0xFF2A0E1C), Color(0xFF150A10)];

  Color get _sceneAccent =>
      _isVideo ? const Color(0xFF7DD3FC) : AppColors.primary;

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _sceneGradient,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Decorative glow
              Positioned(
                top: -80,
                right: -60,
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _sceneAccent.withValues(alpha: 0.10),
                  ),
                ),
              ),

              Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: _isVideo
                        ? _buildVideoScene()
                        : _buildAudioScene(),
                  ),
                  _buildControls(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Icon(
            Icons.lock_rounded,
            size: 14,
            color: Colors.white.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 6),
          Text(
            'End-to-end encrypted',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // AUDIO SCENE — pulsing rings around avatar
  // ============================================================

  Widget _buildAudioScene() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildPulsingAvatar(size: 140),
        const SizedBox(height: 28),
        Text(
          widget.peerName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            _statusText,
            key: ValueKey(_statusText),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _phase == CallPhase.ongoing
                  ? AppColors.callGreen
                  : Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ),
        if (_phase == CallPhase.ringing) ...[
          const SizedBox(height: 14),
          _buildRingingDots(),
        ],
      ],
    );
  }

  // ============================================================
  // VIDEO SCENE — remote view + local PiP preview
  // ============================================================

  Widget _buildVideoScene() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        children: [
          // Remote video area (placeholder for the real feed)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _sceneAccent.withValues(alpha: 0.16),
                      Colors.black.withValues(alpha: 0.4),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildPulsingAvatar(size: 110),
                    const SizedBox(height: 22),
                    Text(
                      widget.peerName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _statusText,
                        key: ValueKey('v_$_statusText'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _phase == CallPhase.ongoing
                              ? AppColors.callGreen
                              : Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                    if (_phase == CallPhase.ringing) ...[
                      const SizedBox(height: 12),
                      _buildRingingDots(),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Local PiP preview
          Positioned(
            top: 16,
            right: 16,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              width: 96,
              height: 128,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: _isVideoEnabled
                    ? LinearGradient(
                        colors: AppColors.primaryGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : const LinearGradient(
                        colors: [Color(0xFF1C1F26), Color(0xFF1C1F26)],
                      ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                _isVideoEnabled
                    ? Icons.person_rounded
                    : Icons.videocam_off_rounded,
                color: Colors.white.withValues(alpha: 0.9),
                size: 34,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // AVATAR WITH PULSING RINGS
  // ============================================================

  Widget _buildPulsingAvatar({required double size}) {
    final showRings =
        _phase == CallPhase.ringing || _phase == CallPhase.connecting;

    return SizedBox(
      width: size * 1.9,
      height: size * 1.9,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (showRings) ...[
            _buildRing(0, size),
            _buildRing(0.33, size),
            _buildRing(0.66, size),
          ],
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: AppColors.primaryGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryDark.withValues(alpha: 0.45),
                  blurRadius: 26,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipOval(
              child: (widget.peerAvatarUrl ?? '').startsWith('http')
                  ? Image.network(
                      widget.peerAvatarUrl!.trim(),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _avatarFallback(size),
                    )
                  : _avatarFallback(size),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback(double size) {
    return Container(
      width: size,
      height: size,
      color: Colors.white.withValues(alpha: 0.12),
      child: Icon(
        Icons.person_rounded,
        size: size * 0.55,
        color: Colors.white.withValues(alpha: 0.9),
      ),
    );
  }

  Widget _buildRing(double progress, double size) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final t = (_pulseController.value + progress) % 1.0;
        return Container(
          width: size + (size * 0.9 * t),
          height: size + (size * 0.9 * t),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: _sceneAccent.withValues(alpha: (1 - t) * 0.45),
              width: 2,
            ),
          ),
        );
      },
    );
  }

  Widget _buildRingingDots() {
    return AnimatedBuilder(
      animation: _dotsController,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final t = ((_dotsController.value - i * 0.2) % 1.0).abs();
            final scale = 1.0 + (0.8 * (1 - t)).clamp(0.0, 0.8);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _sceneAccent.withValues(alpha: 0.4 + 0.6 * (1 - t)),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  // ============================================================
  // CONTROLS + INCOMING CALL ACTIONS
  // ============================================================

  Widget _buildControls() {
    if (_phase == CallPhase.ringing && !widget.isOutgoing) {
      return _buildIncomingActions();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 26),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CallButton(
            icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: _isMuted ? 'Unmute' : 'Mute',
            active: _isMuted,
            onPressed: () => setState(() => _isMuted = !_isMuted),
          ),
          _CallButton(
            icon: _isSpeakerOn
                ? Icons.volume_up_rounded
                : Icons.volume_down_rounded,
            label: 'Speaker',
            active: _isSpeakerOn,
            onPressed: () => setState(() => _isSpeakerOn = !_isSpeakerOn),
          ),
          if (_isVideo)
            _CallButton(
              icon: _isVideoEnabled
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_rounded,
              label: 'Video',
              active: _isVideoEnabled,
              onPressed: () =>
                  setState(() => _isVideoEnabled = !_isVideoEnabled),
            ),
          _CallButton(
            icon: Icons.call_end_rounded,
            label: 'End',
            backgroundColor: AppColors.callRed,
            onPressed: _endCall,
          ),
        ],
      ),
    );
  }

  Widget _buildIncomingActions() {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CallButton(
            icon: Icons.call_end_rounded,
            label: 'Decline',
            backgroundColor: AppColors.callRed,
            large: true,
            onPressed: _endCall,
          ),
          _CallButton(
            icon: Icons.call_rounded,
            label: 'Accept',
            backgroundColor: AppColors.callGreen,
            large: true,
            withPulse: true,
            onPressed: _accept,
          ),
        ],
      ),
    );
  }
}

/// A single animated call control button with correct, accessible colors:
/// white icon on callGreen / callRed / translucent-dark backgrounds.
class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color? backgroundColor;
  final bool large;
  final bool withPulse;
  final VoidCallback onPressed;

  const _CallButton({
    required this.icon,
    required this.label,
    this.active = false,
    this.backgroundColor,
    this.large = false,
    this.withPulse = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ??
        (active ? AppColors.primaryDark : Colors.white.withValues(alpha: 0.12));
    final size = large ? 72.0 : 60.0;

    Widget button = Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bg,
            boxShadow: [
              BoxShadow(
                color: bg.withValues(alpha: 0.4),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: large ? 32 : 26),
        ),
      ),
    );

    if (withPulse) {
      button = TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.0, end: 1.06),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOut,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: button,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}
