import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_radius.dart';

/// ============================================================
/// APP NOTIFICATION OVERLAY — animated in-app toast, top of screen.
/// ============================================================
///
/// Replaces the old bottom SnackBar everywhere in the app:
///
///   showAppNotification(context, 'Logged in successfully!',
///       type: AppNotificationType.success);
///
/// Behaviour:
///  - Slides down from the top with a fade+scale entrance, reverses on exit.
///  - Auto-dismisses after a few seconds (errors stay a bit longer).
///  - Can be swiped up (or tapped) to dismiss manually.
///  - Uses the shared rounded design system (AppRadius).
enum AppNotificationType { success, error, info, warning }

/// Show an animated overlay notification (top of the screen).
///
/// [color] overrides the default color for [type] (used by callers that
/// previously passed a custom snackbar background color).
void showAppNotification(
  BuildContext context,
  String message, {
  String? title,
  AppNotificationType type = AppNotificationType.info,
  Color? color,
  Duration? duration,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  AppNotificationOverlay.show(
    overlay,
    message,
    title: title,
    type: type,
    color: color,
    duration: duration,
  );
}

class AppNotificationOverlay {
  AppNotificationOverlay._();

  static OverlayEntry? _current;
  static VoidCallback? _currentDismiss;

  /// Only one notification is visible at a time — a new one replaces the
  /// previous one (dismissed instantly, without playing the exit animation,
  /// so the new one can come in right away).
  static void show(
    OverlayState overlay,
    String message, {
    String? title,
    AppNotificationType type = AppNotificationType.info,
    Color? color,
    Duration? duration,
  }) {
    _currentDismiss?.call();
    _current?.remove();
    _current = null;
    _currentDismiss = null;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _AppNotificationOverlay(
        message: message,
        title: title,
        type: type,
        color: color,
        duration: duration,
        onDismissed: () {
          _current = null;
          _currentDismiss = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );

    _current = entry;
    overlay.insert(entry);
  }
}

class _AppNotificationOverlay extends StatefulWidget {
  const _AppNotificationOverlay({
    required this.message,
    required this.onDismissed,
    this.title,
    this.type = AppNotificationType.info,
    this.color,
    this.duration,
  });

  final String message;
  final String? title;
  final AppNotificationType type;
  final Color? color;
  final Duration? duration;
  final VoidCallback onDismissed;

  @override
  State<_AppNotificationOverlay> createState() =>
      _AppNotificationOverlayState();
}

class _AppNotificationOverlayState extends State<_AppNotificationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  Timer? _autoDismissTimer;

  double _dragOffset = 0;
  bool _dismissed = false;

  Color get _color {
    if (widget.color != null) return widget.color!;
    switch (widget.type) {
      case AppNotificationType.success:
        return const Color(0xFF16A34A);
      case AppNotificationType.error:
        return const Color(0xFFDC2626);
      case AppNotificationType.warning:
        return const Color(0xFFF59E0B);
      case AppNotificationType.info:
        return const Color(0xFF2563EB);
    }
  }

  IconData get _icon {
    switch (widget.type) {
      case AppNotificationType.success:
        return Icons.check_circle_rounded;
      case AppNotificationType.error:
        return Icons.error_rounded;
      case AppNotificationType.warning:
        return Icons.warning_amber_rounded;
      case AppNotificationType.info:
        return Icons.info_rounded;
    }
  }

  Duration get _duration =>
      widget.duration ??
      (widget.type == AppNotificationType.error
          ? const Duration(milliseconds: 4200)
          : const Duration(milliseconds: 3200));

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    final curved =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.4),
      end: Offset.zero,
    ).animate(curved);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.94, end: 1).animate(curved);

    _controller.forward();
    _autoDismissTimer = Timer(_duration, _dismiss);
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    _autoDismissTimer?.cancel();
    _controller.reverse().whenComplete(() => widget.onDismissed());
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    // Only allow dragging upwards (away).
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dy).clamp(-220.0, 0.0);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dragOffset < -70 ||
        (details.primaryVelocity ?? 0) < -420) {
      _dismiss();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF23252B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1F2937);
    final subTextColor = isDark ? Colors.white70 : const Color(0xFF4B5563);
    final hasTitle =
        widget.title != null && widget.title!.trim().isNotEmpty;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: SafeArea(
            minimum: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismiss,
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onVerticalDragEnd: _onVerticalDragEnd,
              child: Transform.translate(
                offset: Offset(0, _dragOffset),
                child: ScaleTransition(
                  scale: _scale,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: AppRadius.card,
                      border: Border.all(
                        color: _color.withValues(alpha: 0.25),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Icon badge.
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: _color.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(_icon, color: _color, size: 22),
                        ),
                        const SizedBox(width: 12),
                        // Title + message.
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (hasTitle)
                                Text(
                                  widget.title!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14.5,
                                  ),
                                ),
                              Text(
                                widget.message,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: hasTitle ? subTextColor : textColor,
                                  fontWeight:
                                      hasTitle ? FontWeight.w500 : FontWeight.w700,
                                  fontSize: 13.5,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _dismiss,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: subTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
