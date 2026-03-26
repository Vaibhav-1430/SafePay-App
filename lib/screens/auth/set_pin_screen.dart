import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/auth_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/trust_badge.dart';

class SetPinScreen extends StatefulWidget {
  const SetPinScreen({super.key});

  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _isLoading = false;
  bool _navigated = false;
  int _pinLength = 4;

  void _navigateOnce(String route) {
    if (_navigated || !mounted) return;
    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.go(route);
      }
    });
  }

  final _pinTheme = PinTheme(
    width: 58,
    height: 58,
    textStyle: AppTypography.tabular.copyWith(fontSize: 22),
    decoration: BoxDecoration(
      color: AppTheme.darkCard,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppTheme.darkDivider, width: 1),
    ),
  );

  Future<void> _setPin() async {
    if (_isLoading || _navigated) return;

    final pin = _pinController.text;
    final confirmPin = _confirmPinController.text;

    if (!RegExp(r'^\d+$').hasMatch(pin) || pin.length != _pinLength) {
      AppSnackBar.showError(context, 'Please enter a $_pinLength digit PIN');
      return;
    }
    if (pin != confirmPin) {
      AppSnackBar.showError(context, 'PINs do not match');
      return;
    }

    setState(() => _isLoading = true);
    final auth = context.read<AuthService>();
    final result = await auth.setUpiPin(pin);
    if (!mounted) return;

    setState(() => _isLoading = false);
    if (result.success) {
      AppSnackBar.showSuccess(context, result.message);
      _navigateOnce('/home');
    } else {
      AppSnackBar.showError(context, result.message);
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              // Lock icon — premium double-ring (matching PinEntryScreen)
              Stack(
                alignment: Alignment.center,
                children: [
                   // Outer ring
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.10),
                        width: 1.5,
                      ),
                    ),
                  ),
                  // Inner circle
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppTheme.darkElevated,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(Icons.lock_rounded,
                        color: AppTheme.primaryColor, size: 36),
                  ),
                ],
              ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
              const SizedBox(height: 32),
              Text(
                'Set Your UPI PIN',
                style: AppTypography.headlineLarge,
              ).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 8),
              Text(
                'This PIN will be used to authorize\nyour payments',
                textAlign: TextAlign.center,
                style: AppTypography.body,
              ).animate().fadeIn(delay: 300.ms),
              const SizedBox(height: 40),
              // Enter PIN
              Text(
                'Choose PIN length',
                style: AppTypography.label,
              ).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [4, 6].map((len) {
                  return ChoiceChip(
                    label: Text('$len-digit'),
                    selected: _pinLength == len,
                    onSelected: _isLoading
                        ? null
                        : (_) {
                            setState(() {
                              _pinLength = len;
                            });
                            _pinController.clear();
                            _confirmPinController.clear();
                          },
                  );
                }).toList(),
              ).animate().fadeIn(delay: 420.ms),
              const SizedBox(height: 16),
              Pinput(
                key: ValueKey('set-pin-$_pinLength'),
                controller: _pinController,
                length: _pinLength,
                obscureText: true,
                obscuringCharacter: '●',
                defaultPinTheme: _pinTheme,
                focusedPinTheme: _pinTheme.copyWith(
                  decoration: _pinTheme.decoration!.copyWith(
                    border: Border.all(
                        color: AppTheme.primaryColor, width: 1.5),
                  ),
                ),
                submittedPinTheme: _pinTheme.copyWith(
                  decoration: _pinTheme.decoration!.copyWith(
                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                    border: Border.all(
                        color: AppTheme.primaryColor, width: 1),
                  ),
                ),
              ).animate().fadeIn(delay: 450.ms),
              const SizedBox(height: 32),
              Text(
                'Confirm PIN',
                style: AppTypography.label,
              ).animate().fadeIn(delay: 500.ms),
              const SizedBox(height: 16),
              Pinput(
                key: ValueKey('confirm-pin-$_pinLength'),
                controller: _confirmPinController,
                length: _pinLength,
                obscureText: true,
                obscuringCharacter: '●',
                defaultPinTheme: _pinTheme,
                focusedPinTheme: _pinTheme.copyWith(
                  decoration: _pinTheme.decoration!.copyWith(
                    border: Border.all(
                        color: AppTheme.secondaryColor, width: 1.5),
                  ),
                ),
                submittedPinTheme: _pinTheme.copyWith(
                  decoration: _pinTheme.decoration!.copyWith(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.08),
                    border: Border.all(
                        color: AppTheme.secondaryColor, width: 1),
                  ),
                ),
                onCompleted: (_) => _setPin(),
              ).animate().fadeIn(delay: 550.ms),
              const SizedBox(height: 24),
              // Encryption label
              const EncryptionLabel().animate().fadeIn(delay: 580.ms),
              const SizedBox(height: 48),
              PrimaryButton(
                label: 'Set PIN & Continue',
                onPressed: _setPin,
                isLoading: _isLoading,
                icon: Icons.check_rounded,
              ).animate().fadeIn(delay: 600.ms),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => _navigateOnce('/home'),
                child: Text(
                  'Skip for now',
                  style: GoogleFonts.inter(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ).animate().fadeIn(delay: 700.ms),
            ],
          ),
        ),
      ),
    );
  }
}
