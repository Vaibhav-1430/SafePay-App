import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pinput/pinput.dart';
import '../../services/auth_service.dart';
import '../../widgets/common_widgets.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _pinController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;
  Timer? _cooldownTicker;
  int _cooldownSeconds = 0;

  @override
  void initState() {
    super.initState();
    _startCooldownTicker();
  }

  @override
  void dispose() {
    _cooldownTicker?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  void _startCooldownTicker() {
    _cooldownTicker?.cancel();
    _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = context.read<AuthService>().otpCooldownSecondsRemaining;
      if (next != _cooldownSeconds) {
        setState(() => _cooldownSeconds = next);
      }
    });
  }

  Future<void> _resendOtp() async {
    if (_cooldownSeconds > 0) return;
    setState(() => _isResending = true);
    final auth = context.read<AuthService>();
    final error = await auth.resendLastOtp();

    if (!mounted) return;
    setState(() => _isResending = false);
    if (error != null) {
      setState(() => _cooldownSeconds = auth.otpCooldownSecondsRemaining);
      final message = auth.formatOtpError(error);
      if (auth.shouldOfferOtpRetry(message)) {
        AppSnackBar.showErrorWithAction(
          context,
          message,
          actionLabel: 'Retry',
          onAction: _resendOtp,
        );
      } else {
        AppSnackBar.showError(context, message);
      }
      return;
    }
    setState(() => _cooldownSeconds = auth.otpCooldownSecondsRemaining);
    AppSnackBar.showSuccess(context, 'OTP resent successfully.');
  }

  Future<void> _verifyOtp() async {
    if (_pinController.text.length != 6) return;
    setState(() => _isLoading = true);

    final auth = context.read<AuthService>();
    final error = await auth.verifyOTP(_pinController.text);

    if (mounted) {
      setState(() => _isLoading = false);
      if (error != null) {
        final message = auth.formatOtpError(error);
        if (auth.shouldOfferOtpRetry(message)) {
          AppSnackBar.showErrorWithAction(
            context,
            message,
            actionLabel: 'Retry',
            onAction: _verifyOtp,
          );
        } else {
          AppSnackBar.showError(context, message);
        }
      } else {
        // Router redirect already handles authenticated flow; avoid duplicate
        // navigation that can race with provider disposal.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.watch<AuthService>().pendingOtpPhone;
    final defaultPinTheme = PinTheme(
      width: 56,
      height: 60,
      textStyle: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.darkDivider),
      ),
    );

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => context.pop(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(height: 48),
              const Icon(Icons.sms_outlined,
                  color: AppTheme.primaryColor, size: 48)
                  .animate()
                  .scale(duration: 600.ms, curve: Curves.elasticOut),
              const SizedBox(height: 24),
              const Text(
                'Enter OTP',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ).animate().fadeIn(delay: 100.ms),
              const SizedBox(height: 8),
              Text(
                phone == null || phone.isEmpty
                    ? 'We sent a 6-digit code to your phone'
                    : 'We sent a 6-digit code to $phone',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 15,
                ),
              ).animate().fadeIn(delay: 200.ms),
              if (_cooldownSeconds > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'You can resend OTP in ${_cooldownSeconds}s',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 13,
                  ),
                ).animate().fadeIn(delay: 220.ms),
              ],
              const SizedBox(height: 48),
              Center(
                child: Pinput(
                  controller: _pinController,
                  length: 6,
                  defaultPinTheme: defaultPinTheme,
                  focusedPinTheme: defaultPinTheme.copyWith(
                    decoration: defaultPinTheme.decoration!.copyWith(
                      border:
                          Border.all(color: AppTheme.primaryColor, width: 2),
                    ),
                  ),
                  onCompleted: (_) => _verifyOtp(),
                ),
              ).animate().fadeIn(delay: 300.ms),
              const SizedBox(height: 40),
              PrimaryButton(
                label: 'Verify OTP',
                onPressed: _verifyOtp,
                isLoading: _isLoading,
              ).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: (_isLoading || _isResending || _cooldownSeconds > 0)
                      ? null
                      : _resendOtp,
                  child: Text(
                    _isResending
                        ? 'Resending...'
                        : _cooldownSeconds > 0
                            ? 'Resend in ${_cooldownSeconds}s'
                            : 'Resend OTP',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
