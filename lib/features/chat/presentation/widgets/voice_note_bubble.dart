import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_color.dart';
import 'package:pacific_dating_app/core/widgets/app_notification_overlay.dart';
import 'package:pacific_dating_app/core/constants/app_radius.dart';

/// Voice note (audio message) player bubble — inatumika kwenye
/// IndividualChatScreen kwa messages zenye type == 'audio'.
///
/// Inaruhusu mpokeaji (na hata mtumaji) kucheza/kusimamisha ujumbe wa
/// sauti moja kwa moja kwenye bubble:
///  - Play/pause toggle
///  - Progress bar (position/duration)
///  - Muda (duration) na nafasi ya sasa
///
/// Kila bubble ina AudioPlayer yake — haiingiliani na player nyingine.
/// URL ni link ya Supabase Storage (bucket: chat_media) iliyohifadhiwa
/// kwenye messages.media_url wakati ujumbe ulipotumwa.
class VoiceNoteBubble extends StatefulWidget {
  final String mediaUrl;
  final bool isMe;
  final bool isLuxury;

  const VoiceNoteBubble({
    super.key,
    required this.mediaUrl,
    required this.isMe,
    required this.isLuxury,
  });

  @override
  State<VoiceNoteBubble> createState() => _VoiceNoteBubbleState();
}

class _VoiceNoteBubbleState extends State<VoiceNoteBubble> {
  final AudioPlayer _player = AudioPlayer();

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerState _state = PlayerState.stopped;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();

    _durSub = _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    });
    _posSub = _player.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
    });

    _probeDuration();
  }

  /// Inajaribu kupata duration mara moja (kufungua faili bila sauti) —
  /// badala ya kusubiri mtumiaji abonyeze play.
  Future<void> _probeDuration() async {
    try {
      await _player.setSource(UrlSource(widget.mediaUrl));
      await _player.seek(Duration.zero);
      await _player.pause();
    } catch (_) {
      // Duration itapatikana wakati play ianze — hii ni best-effort tu.
    }
  }

  Future<void> _togglePlayPause() async {
    try {
      if (_state == PlayerState.playing) {
        await _player.pause();
        return;
      }

      if (_state == PlayerState.paused) {
        await _player.resume();
        return;
      }

      // stopped / completed -> anza mpya.
      if (_state == PlayerState.completed) {
        await _player.seek(Duration.zero);
      }
      await _player.play(UrlSource(widget.mediaUrl));
    } catch (e) {
      debugPrint('VoiceNote play failed: $e');
      if (mounted) {
        showAppNotification(context, 'Could not play this voice note.');
      }
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    try {
      _player.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isPlaying = _state == PlayerState.playing;
    final bool done = _duration > Duration.zero;
    final double progress =
        done && _duration.inMilliseconds > 0
            ? (_position.inMilliseconds / _duration.inMilliseconds)
                .clamp(0.0, 1.0)
            : 0.0;

    // FIXED palette: white-on-rose for MY bubbles, rose-on-white for peer
    // bubbles — matches the unified chat gradient (isLuxury is legacy and
    // intentionally ignored so voice notes never tint per user).
    final Color iconColor =
        widget.isMe ? Colors.white : AppColors.primaryDeep;
    final Color trackColor = widget.isMe
        ? Colors.white.withValues(alpha: 0.25)
        : AppColors.primary.withValues(alpha: 0.25);
    final Color barColor = widget.isMe ? Colors.white : AppColors.primary;
    final Color textColor = widget.isMe
        ? Colors.white.withValues(alpha: 0.85)
        : Colors.black54;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // PLAY / PAUSE button
          GestureDetector(
            onTap: _togglePlayPause,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isMe
                    ? Colors.white.withValues(alpha: 0.2)
                    : AppColors.primary.withValues(alpha: 0.12),
                border: Border.all(
                  color: widget.isMe
                      ? Colors.white.withValues(alpha: 0.6)
                      : AppColors.primary.withValues(alpha: 0.5),
                  width: 1.4,
                ),
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: iconColor,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // PROGRESS BAR + TIMES
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 5,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: trackColor,
                        borderRadius: AppRadius.sm,
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: progress,
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: AppRadius.sm,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${_fmt(_position)} / ${done ? _fmt(_duration) : '--:--'}',
                  style: TextStyle(fontSize: 10.5, color: textColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.mic_rounded,
            size: 16,
            color: iconColor.withValues(alpha: 0.8),
          ),
        ],
      ),
    );
  }
}
