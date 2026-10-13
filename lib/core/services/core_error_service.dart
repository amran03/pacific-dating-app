import 'package:flutter/material.dart';

import '../widgets/app_notification_overlay.dart';

/// Centralized service for handling and displaying errors across the application.
/// This allows for consistent UI styling and easy integration with logging services.
///
/// All messages are shown with the animated overlay notification
/// (top of the screen, rounded, auto-dismiss + swipe-to-dismiss) instead of
/// the old bottom SnackBar.
class CoreErrorService {
  static final CoreErrorService _instance = CoreErrorService._internal();
  factory CoreErrorService() => _instance;
  CoreErrorService._internal();

  /// Displays a standardized overlay notification to the user.
  ///
  /// [color] is kept for backwards compatibility with old call sites that
  /// passed a custom snackbar background color (e.g. Colors.green for
  /// success messages).
  void showError(
    BuildContext context,
    String message, {
    Color? color,
    String? title,
  }) {
    AppNotificationType type = AppNotificationType.error;
    if (color != null) {
      // Common legacy mappings.
      if (color == Colors.green || color == Colors.greenAccent) {
        type = AppNotificationType.success;
      } else if (color == Colors.orange ||
          color == Colors.orangeAccent ||
          color == Colors.amber) {
        type = AppNotificationType.warning;
      } else if (color == Colors.blue || color == Colors.blueAccent) {
        type = AppNotificationType.info;
      }
    }
    if (title == null && type == AppNotificationType.error) {
      title = 'Something went wrong';
    }
    showAppNotification(context, message, title: title, type: type);
  }

  /// Maps technical exceptions to user-friendly error messages.
  String mapExceptionToMessage(dynamic exception) {
    final errorString = exception.toString().toLowerCase();
    if (errorString.contains('insufficient_coins')) {
      return "You don't have enough Pacific Coins to perform this action. 🪙";
    }
    if (errorString.contains('user-not-found')) {
      return "The requested user profile could not be found.";
    }
    if (errorString.contains('network-error')) {
      return "Please check your internet connection and try again.";
    }
    return "Something went wrong. Please try again later.";
  }
}
