import 'package:firebase_auth/firebase_auth.dart';

class AppErrorHandler {
  static String toUserMessage(
    Object error, {
    String fallback = 'Something went wrong. Please try again.',
  }) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'network-request-failed':
          return 'Network error. Check your connection and retry.';
        case 'user-not-found':
          return 'Account not found. Please sign up first.';
        case 'too-many-requests':
          return 'Too many requests. Please wait a moment and retry.';
        default:
          return error.message ?? fallback;
      }
    }

    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'You do not have permission to perform this action.';
        case 'unavailable':
        case 'deadline-exceeded':
        case 'aborted':
          return 'Network is unstable right now. Please retry.';
        default:
          return error.message ?? fallback;
      }
    }

    if (error is FirebaseException) {
      switch (error.code) {
        case 'unauthorized':
          return 'You are not allowed to upload this image.';
        case 'canceled':
          return 'Upload was canceled.';
        case 'retry-limit-exceeded':
          return 'Upload failed due to network issues. Please retry.';
        default:
          return error.message ?? fallback;
      }
    }

    final text = error.toString().toLowerCase();
    if (text.contains('network') || text.contains('socket')) {
      return 'No internet connection. We will sync when you are back online.';
    }
    return fallback;
  }

  static bool isRetryableNetworkError(Object error) {
    if (error is FirebaseException) {
      return error.code == 'unavailable' ||
          error.code == 'deadline-exceeded' ||
          error.code == 'aborted' ||
          error.code == 'internal';
    }

    final text = error.toString().toLowerCase();
    return text.contains('network') ||
        text.contains('socket') ||
        text.contains('timeout') ||
        text.contains('unavailable');
  }
}
