import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/common_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final auth = context.read<AuthService>();
    final error = await auth.startLoginOtp(phone: _phoneController.text.trim());

    if (mounted) {
      setState(() => _isLoading = false);
      if (error != null) {
        final message = auth.formatOtpError(error);
        if (auth.shouldOfferOtpRetry(message)) {
          AppSnackBar.showErrorWithAction(
            context,
            message,
            actionLabel: 'Retry',
            onAction: _sendOtp,
          );
        } else {
          AppSnackBar.showError(context, message);
        }
      } else {
        if (!auth.isAuthenticated && context.mounted) {
          context.go('/auth/otp?mode=login');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                // Header
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primaryColor, AppTheme.secondaryColor],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.shield_rounded,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'SafePay',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ).animate().fadeIn().slideX(begin: -0.3),
                const SizedBox(height: 48),
                const Text(
                  'Sign in with phone',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.3),
                const SizedBox(height: 8),
                Text(
                  'Secure OTP-based login only',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ).animate().fadeIn(delay: 200.ms),
                const SizedBox(height: 40),
                // Phone field
                AppTextField(
                  controller: _phoneController,
                  label: 'Phone Number',
                  hint: '+91 98765 43210',
                  keyboardType: TextInputType.phone,
                  prefixIcon: Icons.phone_outlined,
                  validator: Validators.validatePhone,
                ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2),
                const SizedBox(height: 16),
                const SizedBox(height: 20),
                // Login button
                PrimaryButton(
                  label: 'Send OTP',
                  onPressed: _sendOtp,
                  isLoading: _isLoading,
                  icon: Icons.sms_outlined,
                ).animate().fadeIn(delay: 550.ms).slideY(begin: 0.2),
                const SizedBox(height: 24),
                // Create account
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                    ),
                    GestureDetector(
                      onTap: () => context.go('/auth/role-selection'),
                      child: const Text(
                        'Create Account',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 600.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
