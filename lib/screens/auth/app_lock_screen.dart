import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../widgets/common_widgets.dart';

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _hasExistingPin = false;
  bool _navigated = false;

  void _goHomeOnce() {
    if (_navigated || !mounted) return;
    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.go('/home');
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _loadPinState();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _loadPinState() async {
    final auth = context.read<AuthService>();
    final hasPin = await auth.hasAppLockPin();
    if (!mounted) return;
    setState(() {
      _hasExistingPin = hasPin;
      _isLoading = false;
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting || _navigated) return;

    final pin = _pinController.text.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      AppSnackBar.showError(context, 'Enter a valid 4 to 6 digit app PIN.');
      return;
    }

    setState(() => _isSubmitting = true);
    final auth = context.read<AuthService>();

    bool ok;
    if (_hasExistingPin) {
      ok = await auth.verifyAppLockPin(pin);
      if (!ok && mounted) {
        AppSnackBar.showError(context, 'Incorrect app PIN.');
      }
    } else {
      final confirm = _confirmPinController.text.trim();
      if (pin != confirm) {
        if (mounted) {
          AppSnackBar.showError(context, 'PIN and confirmation do not match.');
        }
        setState(() => _isSubmitting = false);
        return;
      }
      ok = await auth.setAppLockPin(pin);
      if (!ok && mounted) {
        AppSnackBar.showError(context, 'Failed to save app PIN.');
      }
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (ok) {
      _goHomeOnce();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pinTheme = PinTheme(
      width: 56,
      height: 58,
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
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 36),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.lock_outline_rounded,
                        color: AppTheme.primaryColor,
                        size: 32,
                      ),
                    ).animate().scale(duration: 450.ms),
                    const SizedBox(height: 26),
                    Text(
                      _hasExistingPin ? 'Unlock SafePay' : 'Set App Lock PIN',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ).animate().fadeIn(delay: 100.ms),
                    const SizedBox(height: 8),
                    Text(
                      _hasExistingPin
                          ? 'Enter your app PIN to continue.'
                          : 'Create a PIN required every time you open the app.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 15,
                      ),
                    ).animate().fadeIn(delay: 180.ms),
                    const SizedBox(height: 36),
                    Text(
                      _hasExistingPin ? 'App PIN' : 'Create PIN',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
                    ),
                    const SizedBox(height: 12),
                    Pinput(
                      controller: _pinController,
                      length: 4,
                      obscureText: true,
                      obscuringCharacter: '●',
                      defaultPinTheme: pinTheme,
                      focusedPinTheme: pinTheme.copyWith(
                        decoration: pinTheme.decoration!.copyWith(
                          border: Border.all(color: AppTheme.primaryColor, width: 2),
                        ),
                      ),
                    ).animate().fadeIn(delay: 240.ms),
                    if (!_hasExistingPin) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Confirm PIN',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
                      ),
                      const SizedBox(height: 12),
                      Pinput(
                        controller: _confirmPinController,
                        length: 4,
                        obscureText: true,
                        obscuringCharacter: '●',
                        defaultPinTheme: pinTheme,
                        focusedPinTheme: pinTheme.copyWith(
                          decoration: pinTheme.decoration!.copyWith(
                            border: Border.all(color: AppTheme.secondaryColor, width: 2),
                          ),
                        ),
                      ).animate().fadeIn(delay: 320.ms),
                    ],
                    const Spacer(),
                    PrimaryButton(
                      label: _hasExistingPin ? 'Unlock App' : 'Save App PIN',
                      onPressed: _submit,
                      isLoading: _isSubmitting,
                      icon: _hasExistingPin
                          ? Icons.lock_open_rounded
                          : Icons.check_circle_outline,
                    ).animate().fadeIn(delay: 420.ms),
                    const SizedBox(height: 12),
                    if (_hasExistingPin)
                      SecondaryButton(
                        label: 'Sign Out',
                        onPressed: () async {
                          final auth = context.read<AuthService>();
                          await auth.signOut();
                          if (!context.mounted) return;
                          context.go('/auth/login');
                        },
                      ).animate().fadeIn(delay: 470.ms),
                  ],
                ),
        ),
      ),
    );
  }
}
