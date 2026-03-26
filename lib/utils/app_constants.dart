import 'package:intl/intl.dart';

class AppConstants {
  static const String appName = 'SafePay';
  static const String version = '1.0.0';
  static const String upiSuffix = '@safepay';
  static const int pinLength = 4;
  static const int escrowTimeoutMinutes = 5;
  static const String backendApiBaseUrl = String.fromEnvironment(
    'SAFEPAY_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8081/api',
  );
  static const String mobileApiKey = String.fromEnvironment(
    'SAFEPAY_MOBILE_API_KEY',
    defaultValue: 'safepay-dev-mobile-key',
  );
}

class Formatters {
  static final _currencyFormatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  static final _currencyFormatterDecimal = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static final _dateFormatter = DateFormat('dd MMM yyyy, hh:mm a');
  static final _shortDateFormatter = DateFormat('dd MMM');
  static final _timeFormatter = DateFormat('hh:mm a');

  static String formatCurrency(double amount, {bool decimal = false}) {
    return decimal
        ? _currencyFormatterDecimal.format(amount)
        : _currencyFormatter.format(amount);
  }

  static String formatDate(DateTime date) => _dateFormatter.format(date);
  static String formatShortDate(DateTime date) => _shortDateFormatter.format(date);
  static String formatTime(DateTime date) => _timeFormatter.format(date);

  static String formatRelativeTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return formatShortDate(date);
  }

  static String maskUpiId(String upiId) {
    final parts = upiId.split('@');
    if (parts.isEmpty) return upiId;
    final username = parts[0];
    if (username.length <= 4) return upiId;
    return '${username.substring(0, 2)}***${username.substring(username.length - 2)}@${parts.length > 1 ? parts[1] : ''}';
  }
}

class Validators {
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!emailRegex.hasMatch(value)) return 'Enter a valid email';
    return null;
  }

  static String? validatePhone(String? value) {
    if (value == null || value.isEmpty) return 'Phone number is required';
    final phoneRegex = RegExp(r'^\+?[0-9]{10,13}$');
    if (!phoneRegex.hasMatch(value.replaceAll(' ', ''))) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  static String? validateAmount(String? value) {
    if (value == null || value.isEmpty) return 'Amount is required';
    final amount = double.tryParse(value);
    if (amount == null || amount <= 0) return 'Enter a valid amount';
    if (amount > 100000) return 'Amount cannot exceed ₹1,00,000';
    return null;
  }

  static String? validateUpiId(String? value) {
    if (value == null || value.isEmpty) return 'UPI ID is required';
    if (!value.contains('@')) return 'Enter a valid UPI ID (e.g., 9876543210@safepay)';
    return null;
  }

  static String? validatePin(String? value) {
    if (value == null || value.isEmpty) return 'PIN is required';
    if (value.length != 4) return 'PIN must be 4 digits';
    if (!RegExp(r'^\d+$').hasMatch(value)) return 'PIN must be numeric';
    return null;
  }
}
