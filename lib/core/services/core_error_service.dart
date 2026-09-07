import 'package:flutter/material.dart';

/// Centralized service for handling and displaying errors across the application.
/// This allows for consistent UI styling and easy integration with logging services.
class CoreErrorService {
  static final CoreErrorService _instance = CoreErrorService._internal();
  factory CoreErrorService() => _instance;
  CoreErrorService._internal();

  /// Displays a standardized error snackbar to the user.
  void showError(BuildContext context, String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color ?? Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Maps technical exceptions to user-friendly error messages.
  String mapExceptionToMessage(dynamic exception) {
    final errorString = exception.toString().toLowerCase();
    if (errorString.contains('insufficient_coins')) {
      return "You don't have enough Pasific Coins to perform this action. 🪙";
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