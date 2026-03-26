import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../widgets/common_widgets.dart';

class RegisterScreen extends StatefulWidget {
  final String role;
  const RegisterScreen({super.key, required this.role});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _businessNameController = TextEditingController();
  bool _isLoading = false;
  MerchantType _selectedMerchantType = MerchantType.shopkeeper;

  bool get isMerchant => widget.role == 'merchant';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _businessNameController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final auth = context.read<AuthService>();
    final error = await auth.startSignupOtp(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      userType: isMerchant ? UserType.merchant : UserType.personal,
      businessName: isMerchant ? _businessNameController.text.trim() : null,
      merchantType: isMerchant ? _selectedMerchantType : null,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (error != null) {
        final message = auth.formatOtpError(error);
        if (auth.shouldOfferOtpRetry(message)) {
          AppSnackBar.showErrorWithAction(
            context,
            message,
            actionLabel: 'Retry',
            onAction: _register,
          );
        } else {
          AppSnackBar.showError(context, message);
        }
      } else {
        if (!auth.isAuthenticated && context.mounted) {
          context.go('/auth/otp?mode=signup');
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
                const SizedBox(height: 32),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isMerchant
                              ? [AppTheme.secondaryColor, AppTheme.secondaryDark]
                              : [AppTheme.primaryColor, AppTheme.primaryDark],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isMerchant
                            ? Icons.store_rounded
                            : Icons.person_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      isMerchant
                          ? 'Merchant Account'
                          : 'Personal Account',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ).animate().fadeIn(),
                const SizedBox(height: 8),
                Text(
                  'Fill in your details to get started',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                ).animate().fadeIn(delay: 100.ms),
                const SizedBox(height: 32),
                // Name
                AppTextField(
                  controller: _nameController,
                  label: isMerchant ? 'Owner Name' : 'Full Name',
                  hint: 'John Doe',
                  prefixIcon: Icons.person_outline,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Name is required' : null,
                ).animate().fadeIn(delay: 200.ms),
                if (isMerchant) ...[
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _businessNameController,
                    label: 'Business Name',
                    hint: 'My Shop Name',
                    prefixIcon: Icons.store_outlined,
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Business name is required' : null,
                  ).animate().fadeIn(delay: 250.ms),
                  const SizedBox(height: 16),
                  _MerchantTypeDropdown(
                    value: _selectedMerchantType,
                    onChanged: (type) =>
                        setState(() => _selectedMerchantType = type!),
                  ).animate().fadeIn(delay: 300.ms),
                ],
                const SizedBox(height: 16),
                AppTextField(
                  controller: _emailController,
                  label: 'Email Address',
                  hint: 'your@email.com',
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: Icons.email_outlined,
                  validator: Validators.validateEmail,
                ).animate().fadeIn(delay: 350.ms),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _phoneController,
                  label: 'Phone Number',
                  hint: '+91 98765 43210',
                  keyboardType: TextInputType.phone,
                  prefixIcon: Icons.phone_outlined,
                  validator: Validators.validatePhone,
                ).animate().fadeIn(delay: 400.ms),
                const SizedBox(height: 16),
                const SizedBox(height: 32),
                PrimaryButton(
                  label: 'Continue with OTP',
                  onPressed: _register,
                  isLoading: _isLoading,
                  icon: Icons.sms_outlined,
                  gradient: isMerchant
                      ? const LinearGradient(colors: [
                          AppTheme.secondaryColor,
                          AppTheme.secondaryDark,
                        ])
                      : null,
                ).animate().fadeIn(delay: 500.ms),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                    ),
                    GestureDetector(
                      onTap: () => context.go('/auth/login'),
                      child: const Text(
                        'Sign In',
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

class _MerchantTypeDropdown extends StatelessWidget {
  final MerchantType value;
  final ValueChanged<MerchantType?> onChanged;

  const _MerchantTypeDropdown({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.darkDivider),
      ),
      child: Row(
        children: [
          const Icon(Icons.category_outlined,
              color: AppTheme.textSecondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<MerchantType>(
                value: value,
                onChanged: onChanged,
                dropdownColor: AppTheme.darkCard,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                items: MerchantType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(_merchantTypeLabel(type)),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _merchantTypeLabel(MerchantType type) {
    switch (type) {
      case MerchantType.shopkeeper:
        return '🏪 Shopkeeper';
      case MerchantType.autoDriver:
        return '🛺 Auto Driver';
      case MerchantType.cab:
        return '🚕 Cab Driver';
      case MerchantType.streetVendor:
        return '🛒 Street Vendor';
      case MerchantType.other:
        return '🏢 Other';
    }
  }
}
