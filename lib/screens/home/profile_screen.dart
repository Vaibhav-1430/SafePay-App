import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/wallet_service.dart';
import '../../widgets/common_widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  void _showSafeMessage(String message, {bool success = false}) {
    if (!mounted) return;
    if (success) {
      AppSnackBar.showSuccess(context, message);
    } else {
      AppSnackBar.showError(context, message);
    }
  }

  Future<void> _handleDeleteAccount(AuthService auth) async {
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        title: const Text('Delete Account',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to permanently delete your account? This action cannot be undone.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continue', style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );

    if (firstConfirm != true || !mounted) return;

    final typedConfirm = TextEditingController();
    var isDeleting = false;

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              backgroundColor: AppTheme.darkCard,
              title: const Text('Final Confirmation',
                  style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Type DELETE to confirm account removal.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: typedConfirm,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'DELETE',
                      hintStyle: const TextStyle(color: AppTheme.textMuted),
                      filled: true,
                      fillColor: AppTheme.darkBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isDeleting
                      ? null
                      : () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.errorColor,
                  ),
                  onPressed: isDeleting
                      ? null
                      : () async {
                          if (typedConfirm.text.trim().toUpperCase() != 'DELETE') {
                            _showSafeMessage('Please type DELETE to confirm.');
                            return;
                          }

                          setStateDialog(() => isDeleting = true);
                          final result = await auth.deleteAccount();
                          if (!mounted || !ctx.mounted) return;

                          if (result.success) {
                            Navigator.of(ctx).pop(true);
                            // Router redirect will handle auth-route transition.
                            return;
                          }

                          if (result.requiresRecentLogin) {
                            Navigator.of(ctx).pop(false);
                            await _handleDeleteReauthOtp(auth);
                            return;
                          }

                          if (!ctx.mounted) return;
                          setStateDialog(() => isDeleting = false);
                          _showSafeMessage(result.message);
                        },
                  child: isDeleting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Delete Account'),
                ),
              ],
            );
          },
        );
      },
    );

    typedConfirm.dispose();
  }

  Future<void> _handleDeleteReauthOtp(AuthService auth) async {
    final otpController = TextEditingController();
    var isSending = false;
    var isVerifying = false;
    var sent = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              backgroundColor: AppTheme.darkCard,
              title: const Text('Re-authentication Required',
                  style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'For security, verify your account with OTP before deletion.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Enter OTP',
                      counterText: '',
                      hintStyle: const TextStyle(color: AppTheme.textMuted),
                      filled: true,
                      fillColor: AppTheme.darkBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: (isSending || isVerifying)
                      ? null
                      : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: (isSending || isVerifying)
                      ? null
                      : () async {
                          setStateDialog(() => isSending = true);
                          final error = await auth.startDeleteAccountReauthOtp();
                          if (!mounted || !ctx.mounted) return;
                          setStateDialog(() {
                            isSending = false;
                            sent = error == null;
                          });
                          if (error != null) {
                            _showSafeMessage(error);
                          } else {
                            _showSafeMessage('OTP sent successfully.', success: true);
                          }
                        },
                  child: isSending
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send OTP'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.errorColor,
                  ),
                  onPressed: (!sent || isSending || isVerifying)
                      ? null
                      : () async {
                          if (otpController.text.trim().length != 6) {
                            _showSafeMessage('Enter a valid 6-digit OTP.');
                            return;
                          }
                          setStateDialog(() => isVerifying = true);
                          final result = await auth
                              .confirmDeleteAccountWithOtp(otpController.text.trim());
                          if (!mounted || !ctx.mounted) return;
                          setStateDialog(() => isVerifying = false);

                          if (result.success) {
                            Navigator.of(ctx).pop();
                            // Router redirect will handle auth-route transition.
                            return;
                          }

                          _showSafeMessage(result.message);
                        },
                  child: isVerifying
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verify & Delete'),
                ),
              ],
            );
          },
        );
      },
    );

    otpController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    if (user == null) {
      return const Scaffold(
        backgroundColor: AppTheme.darkBg,
        body: SafeArea(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final upiId = auth.upiIdForDisplay(user);

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1A1040), Color(0xFF0D0D2B)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            gradient: user.isMerchant
                                ? const LinearGradient(colors: [
                                    AppTheme.secondaryColor,
                                    AppTheme.secondaryDark
                                  ])
                                : const LinearGradient(colors: [
                                    AppTheme.primaryColor,
                                    AppTheme.primaryDark
                                  ]),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryColor.withValues(alpha: 0.3),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                          child: Center(
                            child: ClipOval(
                              child: _AvatarContent(
                                imageUrl: user.profileImageUrl,
                                displayName: user.displayName,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: AppTheme.darkBg,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: AppTheme.darkDivider),
                            ),
                            child: Icon(
                              user.isMerchant
                                  ? Icons.store_rounded
                                  : Icons.person_rounded,
                              color: user.isMerchant
                                  ? AppTheme.secondaryColor
                                  : AppTheme.primaryColor,
                              size: 14,
                            ),
                          ),
                        ),
                      ],
                    ).animate().scale(
                          duration: 600.ms,
                          curve: Curves.elasticOut,
                        ),
                    const SizedBox(height: 16),
                    Text(
                      user.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ).animate().fadeIn(delay: 200.ms),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: upiId));
                        AppSnackBar.showSuccess(
                            context, 'UPI ID copied!');
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            upiId,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.copy_rounded,
                              color: AppTheme.textMuted, size: 14),
                        ],
                      ),
                    ).animate().fadeIn(delay: 300.ms),
                    const SizedBox(height: 16),
                    // Rating
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...List.generate(5, (i) {
                          return Icon(
                            i < user.reputationScore.floor()
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: AppTheme.accentOrange,
                            size: 18,
                          );
                        }),
                        const SizedBox(width: 6),
                        Text(
                          '${user.reputationScore.toStringAsFixed(1)} / 5.0',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ).animate().fadeIn(delay: 400.ms),
                  ],
                ),
              ),
              // Balance
              StreamBuilder(
                stream: context
                    .read<WalletService>()
                    .watchWallet(user.uid),
                builder: (context, snapshot) {
                  final balance = snapshot.data?.balance ?? 0.0;
                  return Container(
                    margin: const EdgeInsets.all(20),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E1E3A), Color(0xFF2A2165)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Wallet Balance',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                Formatters.formatCurrency(balance),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => context.push('/top-up'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.secondaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Add Money'),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 500.ms);
                },
              ),
              // Menu items
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _MenuItem(
                      icon: Icons.edit_rounded,
                      label: 'Edit Profile / Change Name',
                      onTap: () => context.push('/profile/edit'),
                      color: AppTheme.infoColor,
                    ),
                    _MenuItem(
                      icon: Icons.history_rounded,
                      label: 'Transaction History',
                      onTap: () => context.push('/transactions'),
                    ),
                    _MenuItem(
                      icon: Icons.people_rounded,
                      label: 'Trusted Contacts',
                      onTap: () => context.push('/contacts'),
                    ),
                    _MenuItem(
                      icon: Icons.notifications_rounded,
                      label: 'Notification Settings',
                      onTap: () => context.push('/notification-settings'),
                      color: AppTheme.primaryLight,
                    ),
                    _MenuItem(
                      icon: Icons.qr_code_2_rounded,
                      label: 'My QR Code',
                      onTap: () => context.push('/qr-display'),
                    ),
                    _MenuItem(
                      icon: Icons.lock_rounded,
                      label: 'Change UPI PIN',
                      onTap: () => context.push('/auth/set-pin'),
                    ),
                    if (user.isMerchant)
                      _MenuItem(
                        icon: Icons.store_rounded,
                        label: 'Merchant Settings',
                        onTap: () => context.push('/merchant-settings'),
                        color: AppTheme.secondaryColor,
                      ),
                    _MenuItem(
                      icon: Icons.delete_forever_rounded,
                      label: 'Delete Account',
                      color: AppTheme.errorColor,
                      onTap: () => _handleDeleteAccount(auth),
                    ),
                    const SizedBox(height: 16),
                    _MenuItem(
                      icon: Icons.logout_rounded,
                      label: 'Sign Out',
                      color: AppTheme.errorColor,
                      onTap: () async {
                        await auth.signOut();
                        if (context.mounted) {
                          context.go('/auth/login');
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ).animate().fadeIn(delay: 600.ms),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final itemColor = color ?? Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: color != null
                ? color!.withValues(alpha: 0.2)
                : AppTheme.darkDivider,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: itemColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: itemColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: itemColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                color: color ?? AppTheme.textMuted, size: 14),
          ],
        ),
      ),
    );
  }
}

class _AvatarContent extends StatelessWidget {
  final String? imageUrl;
  final String displayName;

  const _AvatarContent({
    required this.imageUrl,
    required this.displayName,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;
    if (hasImage) {
      return Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        width: 90,
        height: 90,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';
    return Text(
      initial,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 36,
      ),
    );
  }
}
