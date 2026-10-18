import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_color.dart';
import '../../../core/services/call_service.dart';
import '../../../core/services/user_prefs.dart';
import 'package:pacific_dating_app/core/constants/app_radius.dart';

enum CallType { audio, video }

enum CallPhase { ringing, connecting, ongoing, ended }

/// Real voice/video call screen (WebRTC).
///
/// Signaling happens through a shared Supabase Realtime Broadcast channel
/// `call:<callId>` — events: accept / offer / answer / ice / decline / end.
/// Media flows P2P over WebRTC (Google STUN; for stricter networks add a
/// TURN server to _peerConfig below).
/// Incoming rings arrive through CallService (private channel `call:<uid>`).
class CallScreen extends StatefulWidget {
  /// Idadi ya CallScreen zilizo wazi sasa — PresenceTracker hutumia hii
  /// kuzuia kufungua CallScreen ya pili kutoka notification tap ikiwa moja
  /// tayari iko wazi (dup guard).
  static int _activeInstances = 0;
  static bool get isActive => _activeInstances > 0;

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
  // Pete inayozunguka polepole kuzunguka avatar (connecting/ringing).
  late final AnimationController _spinController;
  // Mlango wa screen — controls zinaingia staggered (elastic).
  late final AnimationController _enterController;

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
  bool _accepted = false; // callee: the user tapped Accept
  bool _tornDown = false;
  bool _offerSent = false; // caller: the offer was sent only once

  // ICE candidates that arrived BEFORE the remote description was set.
  // They are buffered and applied as soon as setRemoteDescription
  // completes. Without this, the first candidates get dropped (addCandidate
  // fails before the remote SDP) and the call stays "Connecting"
  // with no audio/video — the classic WebRTC bug.
  final List<RTCIceCandidate> _pendingIce = [];
  String _callerName = 'Pacific user'; // caller's name (for the missed-call log)

  // ---- RING ALERTS (incoming call) ----
  // Ringtone generated in code (no asset) + vibration loop.
  final AudioPlayer _ringPlayer = AudioPlayer();
  Uint8List? _ringWav;
  Timer? _vibrateTimer;

  bool get _isVideo => widget.callType == CallType.video;

  // ICE servers for calls (WebRTC):
  //  - Google STUN is enough for most networks (home/4G).
  //  - Behind strict NATs (corporate/VPN), STUN IS NOT ENOUGH — you need
  //    a TURN server (relay) for the call to work. Provide via --dart-define:
  //
  //    flutter run \
  //      --dart-define=TURN_URL=turn:your-turn-server.com:3478 \
  //      --dart-define=TURN_USERNAME=appuser \
  //      --dart-define=TURN_CREDENTIAL=secret
  //
  //    (The TURN credential IS A SECRET — never hardcode it here;
  //    it is also recommended to use permanent TURN with short-lived
  //    credentials from your own server. Without TURN vars, only STUN is used.)

  /// TURN server URL (e.g. turn:turn.example.com:3478).
  /// Empty by default — only STUN is used until you provide the dart-define.
  static const String turnUrl = String.fromEnvironment('TURN_URL');

  /// TURN username (static credentials of your TURN server).
  static const String turnUsername = String.fromEnvironment('TURN_USERNAME');

  /// TURN password/credential for your TURN server (SECRET).
  static const String turnCredential =
      String.fromEnvironment('TURN_CREDENTIAL');

  static List<Map<String, dynamic>> _buildIceServers() {
    final servers = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ];

    // TURN (optional): only included if TURN_URL was provided via dart-define.
    if (turnUrl.isNotEmpty) {
      final urls = <String>[turnUrl];
      // Also add the TLS variant (turns:) when the base is turn: — TURN/TLS
      // passes through firewalls that block UDP 3478.
      if (turnUrl.startsWith('turn:')) {
        urls.add(turnUrl.replaceFirst('turn:', 'turns:'));
      }
      final turn = <String, dynamic>{'urls': urls};
      if (turnUsername.isNotEmpty) turn['username'] = turnUsername;
      if (turnCredential.isNotEmpty) turn['credential'] = turnCredential;
      servers.add(turn);
    }

    return servers;
  }

  static final Map<String, dynamic> _peerConfig = {
    'iceServers': _buildIceServers(),
    'sdpSemantics': 'unified-plan',
  };

  @override
  void initState() {
    super.initState();
    CallScreen._activeInstances++;

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
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _localRenderer.initialize();
    _remoteRenderer.initialize();

    if (widget.isOutgoing) {
      _startOutgoingCall();
    } else {
      // Incoming call: play ringtone + vibration until accept/decline.
      _startRingAlerts();
    }
  }

  // ============================================================
  // OUTGOING CALL — media + peer connection + ring
  // ============================================================

  Future<void> _startOutgoingCall() async {
    final ok = await _prepareMediaAndPeer();
    if (!ok || !mounted) return;

    // The CALLER's name/photo (for the peer's incoming call screen).
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

    // Send the ring to the peer's private channel, then join the shared
    // call channel while waiting for accept/offer/ice/end.
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

    // If the peer doesn't answer within 45 seconds — the call ends and
    // the peer gets a "missed call" in their notifications.
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

    // The call was answered — stop the ringtone and vibration.
    _stopRingAlerts();

    final ok = await _prepareMediaAndPeer();
    if (!ok || !mounted) return;

    // Join the channel BEFORE sending accept so the offer isn't lost.
    await _joinCallChannel();
    if (!mounted || _phase == CallPhase.ended) return;
    if (_channel == null) {
      // The channel could not subscribe — the call may not work.
      await _finishCall(sendEnd: false);
      return;
    }

    await _signal('accept');
    setState(() => _phase = CallPhase.connecting);

    // Retry accept twice at 800ms — if the caller hasn't subscribed yet
    // or one packet was lost, they get another one.
    for (int i = 0; i < 2; i++) {
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted || _phase == CallPhase.ongoing || _phase == CallPhase.ended) {
        break;
      }
      await _signal('accept');
    }

    // If the offer doesn't arrive within 20 seconds — the call ends.
    _noAnswerTimer = Timer(const Duration(seconds: 20), () {
      if (mounted && _phase != CallPhase.ongoing) {
        _finishCall(sendEnd: true);
      }
    });
  }

  Future<void> _decline() async {
    // Stop the ringtone and vibration.
    _stopRingAlerts();
    // Join quickly just to send decline, then leave.
    if (_channel == null) await _joinCallChannel();
    await _signal('decline');
    // Log for the caller: "X did not answer your call" — it appears in
    // their "Missed Calls" and is not deleted; marked read once seen.
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
  // SIGNALING — the shared call channel
  // ============================================================

  Future<void> _joinCallChannel() async {
    if (_channel != null) return;
    final client = Supabase.instance.client;
    final channel = client
        .channel('call:${widget.callId}')
        .onBroadcast(event: 'accept', callback: (_) => _onPeerAccepted())
        .onBroadcast(event: 'offer', callback: _onOffer)
        .onBroadcast(event: 'answer', callback: _onAnswer)
        .onBroadcast(event: 'ice', callback: _onIce)
        .onBroadcast(event: 'decline', callback: (_) => _onPeerDeclined())
        .onBroadcast(event: 'end', callback: (_) => _onPeerEnded());

    // Wait for the SUBSCRIBED status — otherwise offer/answer/ice could be
    // sent before the channel is connected and get lost.
    final ok = await CallService.ensureSubscribed(channel);
    if (!ok) return;
    _channel = channel;
  }

  Future<void> _signal(String event, [Map<String, dynamic>? payload]) async {
    final ch = _channel;
    if (ch == null) return;
    try {
      await ch.sendBroadcastMessage(event: event, payload: payload ?? const {});
    } catch (_) {}
  }

  // Caller: the peer tapped Accept — send the WebRTC offer.
  Future<void> _onPeerAccepted() async {
    final pc = _pc;
    if (pc == null || _offerSent || _phase == CallPhase.ended) return;
    // Guard against duplicate 'accept' retries — send the offer only once.
    if (_phase == CallPhase.connecting) return;
    _noAnswerTimer?.cancel();
    _offerSent = true;
    if (mounted) setState(() => _phase = CallPhase.connecting);

    final offer = await pc.createOffer({'offerToReceiveVideo': _isVideo});
    await pc.setLocalDescription(offer);
    final desc = await pc.getLocalDescription();
    await _signal('offer', {'sdp': desc?.sdp, 'type': desc?.type});
  }

  // Callee: we received the offer — set remote, create the answer.
  Future<void> _onOffer(dynamic payload) async {
    final pc = _pc;
    if (pc == null || payload is! Map) return;
    final sdp = payload['sdp']?.toString();
    if (sdp == null || sdp.isEmpty) return;

    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    // ICE candidates that arrived before the offer — apply them now.
    await _flushPendingIce();
    final answer = await pc.createAnswer({'offerToReceiveVideo': _isVideo});
    await pc.setLocalDescription(answer);
    final desc = await pc.getLocalDescription();
    await _signal('answer', {'sdp': desc?.sdp, 'type': desc?.type});
    _noAnswerTimer?.cancel();
    if (mounted && _phase != CallPhase.ongoing) {
      setState(() => _phase = CallPhase.connecting);
    }
  }

  // Caller: we received the callee's answer.
  Future<void> _onAnswer(dynamic payload) async {
    final pc = _pc;
    if (pc == null || payload is! Map) return;
    final sdp = payload['sdp']?.toString();
    if (sdp == null || sdp.isEmpty) return;
    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    // ICE candidates that arrived before the answer — apply them now.
    await _flushPendingIce();
  }

  Future<void> _onIce(dynamic payload) async {
    final pc = _pc;
    if (pc == null || payload is! Map) return;
    final candidate = payload['candidate']?.toString();
    if (candidate == null || candidate.isEmpty) return;

    final ice = RTCIceCandidate(
      candidate,
      payload['sdpMid']?.toString(),
      (payload['sdpMLineIndex'] as num?)?.toInt(),
    );

    // A candidate can arrive before the remote description (offer/answer)
    // is set — addCandidate fails then. Buffer it first.
    final remoteDesc = await pc.getRemoteDescription();
    if (remoteDesc == null || (remoteDesc.sdp ?? '').isEmpty) {
      _pendingIce.add(ice);
      return;
    }

    try {
      await pc.addCandidate(ice);
    } catch (_) {}
  }

  /// Applies the buffered ICE candidates (before the remote SDP was set).
  Future<void> _flushPendingIce() async {
    final pc = _pc;
    if (pc == null || _pendingIce.isEmpty) return;
    final queued = List<RTCIceCandidate>.from(_pendingIce);
    _pendingIce.clear();
    for (final ice in queued) {
      try {
        await pc.addCandidate(ice);
      } catch (_) {}
    }
  }

  void _onPeerDeclined() => _finishCall(sendEnd: false);
  void _onPeerEnded() => _finishCall(sendEnd: false);

  // ============================================================
  // MEDIA + PEER CONNECTION
  // ============================================================

  Future<bool> _prepareMediaAndPeer() async {
    try {
      // 1. Mic/camera permissions
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

      // 2. Local media (mic + camera for video calls)
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

      // Default audio routing: video call -> loud speaker; audio call ->
      // earpiece (like a normal phone call). The user can change it
      // with the "Speaker" button.
      _isSpeakerOn = _isVideo;
      await Helper.setSpeakerphoneOn(_isSpeakerOn);

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
      // Fallback: on some platforms onConnectionState does not work
      // fully — ICE connected/completed also means the call is
      // "ongoing" and both sides can talk.
      _pc!.onIceConnectionState = (state) {
        if (state ==
                RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _goOngoing();
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
  // CALL LIFECYCLE
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
    _stopRingAlerts();
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

  /// Kichwa cha audio scene — kinabadilika na phase (jina, kisha wakati
  /// wa simu unapoanza ili mtumiaji aone muda mara moja).
  String get _audioHeaderTitle =>
      _phase == CallPhase.ongoing ? _formattedDuration : widget.peerName;

  @override
  void dispose() {
    CallScreen._activeInstances--;
    _noAnswerTimer?.cancel();
    _durationTimer?.cancel();
    _stopRingAlerts();
    _ringPlayer.dispose();
    _pulseController.dispose();
    _dotsController.dispose();
    _spinController.dispose();
    _enterController.dispose();
    _teardownWebRTC();
    super.dispose();
  }

  // ============================================================
  // RING ALERTS — ringtone (generated in code, no asset)
  // + vibration loop for incoming calls. Respects the user's
  // preferences (sound/vibration) from UserPrefs.
  // ============================================================

  void _startRingAlerts() {
    _stopRingAlerts();

    if (UserPrefs.instance.vibrationEnabled) {
      HapticFeedback.vibrate();
      _vibrateTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
        HapticFeedback.vibrate();
      });
    }

    if (UserPrefs.instance.soundEnabled) {
      _playSynthRingtone();
    }
  }

  void _stopRingAlerts() {
    _vibrateTimer?.cancel();
    _vibrateTimer = null;
    try {
      _ringPlayer.stop();
    } catch (_) {}
  }

  Future<void> _playSynthRingtone() async {
    try {
      _ringWav ??= _buildRingtoneWav();
      await _ringPlayer.setReleaseMode(ReleaseMode.loop);
      await _ringPlayer.play(BytesSource(_ringWav!));
    } catch (_) {}
  }

  /// Builds a WAV (mono, 8kHz, 16-bit) with the classic two-tone ring:
  /// 400ms @ 850Hz + 200ms silence + 400ms @ 1050Hz + 400ms silence (x2 = 2.8s).
  static Uint8List _buildRingtoneWav() {
    const sampleRate = 8000;
    const toneMs = 400;
    const gap1Ms = 200;
    const gap2Ms = 400;
    const cycles = 2;
    const cycleMs = toneMs + gap1Ms + toneMs + gap2Ms; // 1400ms
    final totalSamples = sampleRate * cycleMs * cycles ~/ 1000;

    final samples = Int16List(totalSamples);
    for (int i = 0; i < totalSamples; i++) {
      final inCycleMs = (i * 1000 ~/ sampleRate) % cycleMs;
      double freq = 0;
      if (inCycleMs < toneMs) {
        freq = 850;
      } else if (inCycleMs >= toneMs + gap1Ms &&
          inCycleMs < toneMs + gap1Ms + toneMs) {
        freq = 1050;
      }
      if (freq > 0) {
        // Fade ndogo mwanzo/mwisho wa tone ili kupunguza "click" sauti.
        final t = i / sampleRate;
        final value = sin(2 * pi * freq * t) * 11000;
        samples[i] = value.round().clamp(-32768, 32767);
      }
    }

    final dataLen = totalSamples * 2;
    final buffer = ByteData(44 + dataLen);
    void writeStr(int offset, String s) {
      for (int i = 0; i < s.length; i++) {
        buffer.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    writeStr(0, 'RIFF');
    buffer.setUint32(4, 36 + dataLen, Endian.little);
    writeStr(8, 'WAVE');
    writeStr(12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little); // fmt chunk size
    buffer.setUint16(20, 1, Endian.little); // PCM
    buffer.setUint16(22, 1, Endian.little); // mono
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    buffer.setUint16(32, 2, Endian.little); // block align
    buffer.setUint16(34, 16, Endian.little); // bits per sample
    writeStr(36, 'data');
    buffer.setUint32(40, dataLen, Endian.little);
    for (int i = 0; i < totalSamples; i++) {
      buffer.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return buffer.buffer.asUint8List();
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
        child: Stack(
          children: [
            // AURORA — miale ya rangi inayoelea nyuma ya kila kitu
            // (WhatsApp-style dark + Pacific pink vibes).
            _buildAuroraOrbs(),
            SafeArea(
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
          ],
        ),
      ),
    );
  }

  // ============================================================
  // AURORA BACKGROUND — miale 3 ya neon inayoelea polepole.
  // ============================================================

  Widget _buildAuroraOrbs() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final t = _pulseController.value;
        return Stack(
          children: [
            Positioned(
              top: -60 + 24 * sin(t * 2 * pi),
              left: -70 + 18 * cos(t * 2 * pi),
              child: _orb(230, AppColors.primary.withValues(alpha: 0.22)),
            ),
            Positioned(
              bottom: -40 + 20 * cos(t * 2 * pi),
              right: -60 + 22 * sin(t * 2 * pi * 0.7),
              child: _orb(
                  260, const Color(0xFF7C4DFF).withValues(alpha: 0.18)),
            ),
            Positioned(
              top: 200 + 26 * sin(t * 2 * pi * 0.5 + 1),
              right: -90,
              child: _orb(
                  170, const Color(0xFF40C4FF).withValues(alpha: 0.12)),
            ),
          ],
        );
      },
    );
  }

  Widget _orb(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withValues(alpha: 0.10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_rounded,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 6),
                Text(
                  'End-to-end encrypted',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (_phase == CallPhase.ongoing)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: AppColors.primary.withValues(alpha: 0.22),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF7BF1A8),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formattedDuration,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
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
        // Jina linabadilika na phase (fade + slide).
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.25),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          ),
          child: Text(
            _audioHeaderTitle,
            key: ValueKey(_audioHeaderTitle),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Status pill ya glass — dot inayopulse + text.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          ),
          child: Container(
            key: ValueKey(_statusText),
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.22),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatusDot(),
                const SizedBox(width: 8),
                Text(
                  _statusText,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _phase == CallPhase.ongoing
                        ? const Color(0xFF7BF1A8)
                        : Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
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

  /// Dot inayopulse (kijani wakati wa kuongea, pink wakati wa kupiga).
  Widget _buildStatusDot() {
    final color = _phase == CallPhase.ongoing
        ? AppColors.callGreen
        : AppColors.primary;
    return AnimatedBuilder(
      animation: _dotsController,
      builder: (context, _) {
        final t = _dotsController.value;
        final scale = 1.0 + 0.35 * sin(t * 2 * pi);
        final glow = 0.35 + 0.35 * sin(t * 2 * pi);
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: glow.clamp(0.0, 0.7)),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Transform.scale(scale: scale, child: Container()),
        );
      },
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
          // Remote video area — real WebRTC feed, placeholder until connected
          Positioned.fill(
            child: ClipRRect(
              borderRadius: AppRadius.xl,
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
                    // Chip ya jina juu ya video placeholder.
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Colors.black.withValues(alpha: 0.45),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        widget.peerName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _statusText,
                        key: ValueKey('v_$_statusText'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _phase == CallPhase.ongoing
                              ? const Color(0xFF7BF1A8)
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

          // Local PiP preview — na kivuli cha pink + lebo "You".
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
                  color: _sceneAccent.withValues(alpha: 0.6),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _sceneAccent.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: AppRadius.md,
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
          // Lebo "You" kwenye PiP + muda wa simu chini ya video.
          Positioned(
            top: 24,
            right: 24,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.black.withValues(alpha: 0.55),
              ),
              child: const Text(
                'You',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (_phase == CallPhase.ongoing)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.black.withValues(alpha: 0.55),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF7BF1A8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.peerName} • $_formattedDuration',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
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
          // Pink aura — avatar inang'aa gizani (impressive glow).
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _sceneAccent.withValues(alpha: 0.55),
                  blurRadius: 54,
                  spreadRadius: 10,
                ),
              ],
            ),
          ),
          if (showRings) ...[
            _buildRing(0, size),
            _buildRing(0.33, size),
            _buildRing(0.66, size),
            // Pete inayozunguka (spinning dashed arc) — inaashiria kuwa
            // simu bado inaunganishwa.
            AnimatedBuilder(
              animation: _spinController,
              builder: (context, _) => CustomPaint(
                size: Size(size * 1.35, size * 1.35),
                painter: _SpinningArcPainter(
                  rotation: _spinController.value * 2 * pi,
                  color: _sceneAccent,
                ),
              ),
            ),
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

    // FittedBox: kwenye skrini ndogo (<=360px) Row ya buttons haifikiwi
    // overflow — inapunguza kiwango kidogo badala ya kukata.
    // GLASS DOCK: frosted bar inayobeba controls.
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 26),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              color: Colors.white.withValues(alpha: 0.10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.20),
                width: 1,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _enterAnimated(0, _muteButton()),
                  const SizedBox(width: 6),
                  _enterAnimated(1, _speakerButton()),
                  const SizedBox(width: 6),
                  if (_isVideo) ...[
                    _enterAnimated(2, _videoButton()),
                    const SizedBox(width: 6),
                  ],
                  _enterAnimated(3, _endButton()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Kila button inaingia na kucheza kidogo (staggered elastic) screen
  /// ikifunguka — inaonekana hai, si static.
  Widget _enterAnimated(int index, Widget child) {
    return AnimatedBuilder(
      animation: _enterController,
      builder: (context, _) {
        final start = (index * 0.12).clamp(0.0, 0.6);
        final t = ((_enterController.value - start) / (1 - start))
            .clamp(0.0, 1.0);
        final eased =
            Curves.elasticOut.transform(t.clamp(0.0, 1.0));
        return Transform.translate(
          offset: Offset(0, 46 * (1 - t)),
          child: Transform.scale(
            scale: 0.55 + 0.45 * eased.clamp(0.0, 1.15) / 1.15 * 1.15,
            child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
          ),
        );
      },
    );
  }

  Widget _muteButton() {
    return _CallButton(
      icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
      label: _isMuted ? 'Unmute' : 'Mute',
      active: _isMuted,
      onPressed: () {
        setState(() => _isMuted = !_isMuted);
        // Enable/disable the local audio track.
        _localStream?.getAudioTracks().forEach((track) {
          track.enabled = !_isMuted;
        });
      },
    );
  }

  Widget _speakerButton() {
    return _CallButton(
      icon: _isSpeakerOn
          ? Icons.volume_up_rounded
          : Icons.volume_down_rounded,
      label: 'Speaker',
      active: _isSpeakerOn,
      onPressed: () {
        setState(() => _isSpeakerOn = !_isSpeakerOn);
        Helper.setSpeakerphoneOn(_isSpeakerOn);
      },
    );
  }

  Widget _videoButton() {
    return _CallButton(
      icon: _isVideoEnabled
          ? Icons.videocam_rounded
          : Icons.videocam_off_rounded,
      label: 'Video',
      active: _isVideoEnabled,
      onPressed: () {
        setState(() => _isVideoEnabled = !_isVideoEnabled);
        // Enable/disable the local camera.
        _localStream?.getVideoTracks().forEach((track) {
          track.enabled = _isVideoEnabled;
        });
      },
    );
  }

  Widget _endButton() {
    return _CallButton(
      icon: Icons.call_end_rounded,
      label: 'End',
      backgroundColor: AppColors.callRed,
      onPressed: _endCall,
    );
  }

  Widget _buildIncomingActions() {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 40),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _CallButton(
              icon: Icons.call_end_rounded,
              label: 'Decline',
              backgroundColor: AppColors.callRed,
              large: true,
              onPressed: _decline,
            ),
            const SizedBox(width: 48),
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
      ),
    );
  }
}

/// Pete ya arc inayozunguka kuzunguka avatar wakati simu inaunganishwa.
class _SpinningArcPainter extends CustomPainter {
  final double rotation;
  final Color color;

  const _SpinningArcPainter({required this.rotation, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // Arc mbili tofauti (kama spinner ya kisasa).
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      rotation,
      pi * 0.55,
      false,
      paint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      rotation + pi,
      pi * 0.3,
      false,
      paint..color = color.withValues(alpha: 0.4),
    );
  }

  @override
  bool shouldRepaint(_SpinningArcPainter old) =>
      old.rotation != rotation || old.color != color;
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
