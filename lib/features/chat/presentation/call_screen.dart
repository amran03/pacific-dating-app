import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_color.dart';
import '../../../core/services/call_service.dart';

enum CallType { audio, video }

enum CallPhase { ringing, connecting, ongoing, ended }

/// Real voice/video call screen (WebRTC).
///
/// Signaling inafanyika kupitia Supabase Realtime Broadcast kwenye channel ya
/// pamoja `call:<callId>` — events: accept / offer / answer / ice / decline /
/// end. Media inapita P2P to WebRTC (Google STUN; to mitandao ya ngumu
/// zaidi weka TURN server kwenye _peerConfig chini).
/// Incoming rings zinakuja kupitia CallService (channel ya faragha `call:<uid>`).
class CallScreen extends StatefulWidget {
  final CallType callType;
  final String peerName;
  final String? peerAvatarUrl;
  final bool isOutgoing;
  final String peerUid;
  final String callId;

  const CallScreen({
    super.key,
    required this.callType,
    required this.peerName,
    required this.peerUid,
    required this.callId,
    this.peerAvatarUrl,
    this.isOutgoing = true,
  });

  static Future<void> push(
    BuildContext context, {
    required CallType callType,
    required String peerName,
    required String peerUid,
    required String callId,
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
            peerUid: peerUid,
            callId: callId,
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
  Timer? _noAnswerTimer;
  Timer? _durationTimer;

  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isVideoEnabled = true;

  // ---- WebRTC ----
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RealtimeChannel? _channel;
  bool _localVideoReady = false;
  bool _accepted = false; // callee: mtumiaji amebonyeza Accept
  bool _tornDown = false;
  String _callerName = 'Pacific user'; // jina la caller (kwa missed-call log)

  bool get _isVideo => widget.callType == CallType.video;

  // STUN ya Google inatosha to karibuni mitandao. Kwa NAT kali (corporate
  // n.k.) ongeza TURN server hapa: {'urls': 'turn:...','username':...,'credential':...}
  static const Map<String, dynamic> _peerConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

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

    _localRenderer.initialize();
    _remoteRenderer.initialize();

    if (widget.isOutgoing) {
      _startOutgoingCall();
    }
  }

  // ============================================================
  // OUTGOING CALL — media + peer connection + ring
  // ============================================================

  Future<void> _startOutgoingCall() async {
    final ok = await _prepareMediaAndPeer();
    if (!ok || !mounted) return;

    // Jina/picha ya CALLER (kwa ajili ya incoming call screen ya mwenzake).
    String callerName = 'Pacific user';
    String? callerAvatar;
    try {
      final uid = Supabase.instance.client.auth.currentUser!.id;
      final row = await Supabase.instance.client
          .from('users')
          .select('name, profile_image_url')
          .eq('uid', uid)
          .maybeSingle();
      if (row != null) {
        final n = row['name']?.toString() ?? '';
        if (n.isNotEmpty) callerName = n;
        final img = row['profile_image_url']?.toString() ?? '';
        if (img.isNotEmpty) callerAvatar = img;
      }
    } catch (_) {}
    _callerName = callerName;

    // Tuma ring to channel ya faragha ya mwenzake, kisha jiunge na channel
    // ya pamoja ya call tukingoja accept/offer/ice/end.
    final sent = await CallService.instance.sendRing(
      peerUid: widget.peerUid,
      callId: widget.callId,
      callType: widget.callType,
      callerName: callerName,
      callerAvatarUrl: callerAvatar,
    );
    if (!sent) {
      if (mounted) setState(() => _phase = CallPhase.ended);
      _noAnswerTimer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }

    await _joinCallChannel();

    // Kama mwenzake hajajibu ndani ya sekunde 45 — call inaisha na
    // mwenzake anapata "missed call" kwenye notifications zake.
    _noAnswerTimer = Timer(const Duration(seconds: 45), () {
      if (mounted && _phase != CallPhase.ongoing) {
        CallService.logMissedCall(
          toUid: widget.peerUid,
          fromUid: Supabase.instance.client.auth.currentUser!.id,
          fromName: _callerName,
          isVideo: _isVideo,
        );
        _finishCall(sendEnd: true);
      }
    });
  }

  // ============================================================
  // INCOMING CALL — accept / decline
  // ============================================================

  Future<void> _accept() async {
    if (_accepted || _phase == CallPhase.ended) return;
    _accepted = true;

    final ok = await _prepareMediaAndPeer();
    if (!ok || !mounted) return;

    // Jiunge na channel KABLA ya kutuma accept ili offer isipotee.
    await _joinCallChannel();
    _signal('accept');

    setState(() => _phase = CallPhase.connecting);

    // Kama offer haifiki ndani ya sekunde 20 — call inaisha.
    _noAnswerTimer = Timer(const Duration(seconds: 20), () {
      if (mounted && _phase != CallPhase.ongoing) {
        _finishCall(sendEnd: true);
      }
    });
  }

  Future<void> _decline() async {
    // Jiunge to haraka tu kutuma decline kisha toka.
    if (_channel == null) await _joinCallChannel();
    await _signal('decline');
    // Kumbukumbu to caller: "X did not answer simu yako" — inaonekana kwenye
    // "Missed Calls" zake na haitafutwi; inaashiriwa imesomwa akishaiona.
    String myName = 'Pacific user';
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('name')
          .eq('uid', Supabase.instance.client.auth.currentUser!.id)
          .maybeSingle();
      final n = row?['name']?.toString() ?? '';
      if (n.isNotEmpty) myName = n;
    } catch (_) {}
    CallService.logMissedCall(
      toUid: widget.peerUid,
      fromUid: Supabase.instance.client.auth.currentUser?.id ?? '',
      fromName: myName,
      isVideo: _isVideo,
      declined: true,
    );
    await _finishCall(sendEnd: false);
  }

  // ============================================================
  // SIGNALING — channel ya pamoja ya call
  // ============================================================

  Future<void> _joinCallChannel() async {
    if (_channel != null) return;
    final client = Supabase.instance.client;
    _channel = client
        .channel('call:${widget.callId}')
        .onBroadcast(event: 'accept', callback: (_) => _onPeerAccepted())
        .onBroadcast(event: 'offer', callback: _onOffer)
        .onBroadcast(event: 'answer', callback: _onAnswer)
        .onBroadcast(event: 'ice', callback: _onIce)
        .onBroadcast(event: 'decline', callback: (_) => _onPeerDeclined())
        .onBroadcast(event: 'end', callback: (_) => _onPeerEnded())
        .subscribe();
  }

  Future<void> _signal(String event, [Map<String, dynamic>? payload]) async {
    final ch = _channel;
    if (ch == null) return;
    try {
      await ch.sendBroadcastMessage(event: event, payload: payload ?? const {});
    } catch (_) {}
  }

  // Caller: mwenzake amebonyeza Accept — tuma WebRTC offer.
  Future<void> _onPeerAccepted() async {
    final pc = _pc;
    if (pc == null || _phase == CallPhase.ongoing) return;
    _noAnswerTimer?.cancel();
    if (mounted) setState(() => _phase = CallPhase.connecting);

    final offer = await pc.createOffer({'offerToReceiveVideo': _isVideo});
    await pc.setLocalDescription(offer);
    final desc = await pc.getLocalDescription();
    await _signal('offer', {'sdp': desc?.sdp, 'type': desc?.type});
  }

  // Callee: tunapokea offer — tunaweka remote, tunatengeneza answer.
  Future<void> _onOffer(dynamic payload) async {
    final pc = _pc;
    if (pc == null || payload is! Map) return;
    final sdp = payload['sdp']?.toString();
    if (sdp == null || sdp.isEmpty) return;

    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    final answer = await pc.createAnswer({'offerToReceiveVideo': _isVideo});
    await pc.setLocalDescription(answer);
    final desc = await pc.getLocalDescription();
    await _signal('answer', {'sdp': desc?.sdp, 'type': desc?.type});
    _noAnswerTimer?.cancel();
    if (mounted && _phase != CallPhase.ongoing) {
      setState(() => _phase = CallPhase.connecting);
    }
  }

  // Caller: tunapokea answer ya callee.
  Future<void> _onAnswer(dynamic payload) async {
    final pc = _pc;
    if (pc == null || payload is! Map) return;
    final sdp = payload['sdp']?.toString();
    if (sdp == null || sdp.isEmpty) return;
    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
  }

  Future<void> _onIce(dynamic payload) async {
    final pc = _pc;
    if (pc == null || payload is! Map) return;
    final candidate = payload['candidate']?.toString();
    if (candidate == null || candidate.isEmpty) return;
    try {
      await pc.addCandidate(RTCIceCandidate(
        candidate,
        payload['sdpMid']?.toString(),
        (payload['sdpMLineIndex'] as num?)?.toInt(),
      ));
    } catch (_) {}
  }

  void _onPeerDeclined() => _finishCall(sendEnd: false);
  void _onPeerEnded() => _finishCall(sendEnd: false);

  // ============================================================
  // MEDIA + PEER CONNECTION
  // ============================================================

  Future<bool> _prepareMediaAndPeer() async {
    try {
      // 1. Ruhusa za mic/camera
      final permissions = await [
        Permission.microphone,
        if (_isVideo) Permission.camera,
      ].request();
      if (permissions.values.any((s) => !s.isGranted)) {
        if (mounted) setState(() => _phase = CallPhase.ended);
        _noAnswerTimer = Timer(const Duration(milliseconds: 1800), () {
          if (mounted) Navigator.of(context).pop();
        });
        return false;
      }

      // 2. Media ya local (mic + camera to video call)
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': _isVideo
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
              }
            : false,
      });
      _localRenderer.srcObject = _localStream;
      _localVideoReady = _localStream!.getVideoTracks().isNotEmpty;

      // 3. Peer connection
      _pc = await createPeerConnection(_peerConfig);

      _pc!.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          _remoteRenderer.srcObject = _remoteStream;
          if (mounted) setState(() {});
        }
      };
      _pc!.onIceCandidate = (candidate) {
        if (candidate.candidate == null) return;
        _signal('ice', {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      };
      _pc!.onConnectionState = (state) {
        if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _goOngoing();
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _finishCall(sendEnd: true);
        }
      };

      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }
      return true;
    } catch (_) {
      if (mounted) {
        setState(() => _phase = CallPhase.ended);
        _noAnswerTimer = Timer(const Duration(milliseconds: 1800), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
      return false;
    }
  }

  // ============================================================
  // LIFECYCLE YA CALL
  // ============================================================

  void _goOngoing() {
    if (!mounted ||
        _phase == CallPhase.ongoing ||
        _phase == CallPhase.ended) {
      return;
    }
    _noAnswerTimer?.cancel();
    _pulseController.stop();
    setState(() => _phase = CallPhase.ongoing);
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds += 1);
    });
  }

  void _endCall() => _finishCall(sendEnd: true);

  Future<void> _finishCall({required bool sendEnd}) async {
    _noAnswerTimer?.cancel();
    _durationTimer?.cancel();
    if (sendEnd) await _signal('end');
    await _teardownWebRTC();
    if (!mounted || _phase == CallPhase.ended) return;
    setState(() => _phase = CallPhase.ended);
    Timer(const Duration(milliseconds: 1400), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _teardownWebRTC() async {
    if (_tornDown) return;
    _tornDown = true;
    try {
      final ch = _channel;
      _channel = null;
      if (ch != null) await ch.unsubscribe();
    } catch (_) {}
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    try {
      await _localStream?.dispose();
    } catch (_) {}
    try {
      await _remoteStream?.dispose();
    } catch (_) {}
    _localStream = null;
    _remoteStream = null;
    try {
      await _localRenderer.dispose();
    } catch (_) {}
    try {
      await _remoteRenderer.dispose();
    } catch (_) {}
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
    _noAnswerTimer?.cancel();
    _durationTimer?.cancel();
    _pulseController.dispose();
    _dotsController.dispose();
    _teardownWebRTC();
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
          // Remote video area — real WebRTC feed, placeholder kabla haijaunganisha
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: (_phase == CallPhase.ongoing &&
                      _remoteRenderer.srcObject != null)
                  ? RTCVideoView(
                      _remoteRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : Container(
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16.5),
                child: (_localVideoReady && _isVideoEnabled &&
                        _localRenderer.srcObject != null)
                    ? RTCVideoView(
                        _localRenderer,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        mirror: true,
                      )
                    : Icon(
                        _isVideoEnabled
                            ? Icons.person_rounded
                            : Icons.videocam_off_rounded,
                        color: Colors.white.withValues(alpha: 0.9),
                        size: 34,
                      ),
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
            onPressed: () {
              setState(() => _isMuted = !_isMuted);
              // Tuma/zima audio track ya local.
              _localStream?.getAudioTracks().forEach((track) {
                track.enabled = !_isMuted;
              });
            },
          ),
          _CallButton(
            icon: _isSpeakerOn
                ? Icons.volume_up_rounded
                : Icons.volume_down_rounded,
            label: 'Speaker',
            active: _isSpeakerOn,
            onPressed: () {
              setState(() => _isSpeakerOn = !_isSpeakerOn);
              Helper.setSpeakerphoneOn(_isSpeakerOn);
            },
          ),
          if (_isVideo)
            _CallButton(
              icon: _isVideoEnabled
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_rounded,
              label: 'Video',
              active: _isVideoEnabled,
              onPressed: () {
                setState(() => _isVideoEnabled = !_isVideoEnabled);
                // Zima/tuma camera ya local.
                _localStream?.getVideoTracks().forEach((track) {
                  track.enabled = _isVideoEnabled;
                });
              },
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
            onPressed: _decline,
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
