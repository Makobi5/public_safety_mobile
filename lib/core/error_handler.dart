import 'package:supabase_flutter/supabase_flutter.dart';

class ErrorHandler {
  static String getFriendlyErrorMessage(dynamic e) {
    if (e is AuthException) {
      // Supabase specific error codes
      switch (e.code) {
        case 'invalid_credentials':
          return 'The email or password you entered is incorrect. Please try again.';
        case 'user_not_found':
          return 'No account exists with this email address.';
        case 'network_error':
          return 'Connection failed. Please check your internet and try again.';
        case 'over_email_send_rate_limit':
          return 'Too many attempts. Please wait a minute before trying again.';
        default:
          return e.message; // Fallback to the message if code isn't handled
      }
    }

    // Check for general string errors or network timeouts
    final errorStr = e.toString().toLowerCase();
    if (errorStr.contains('socketexception') || errorStr.contains('network')) {
      return 'Internet connection error. Check your data or Wi-Fi.';
    }

    return 'An unexpected error occurred. Please try again later.';
  }
}
