// =============================================================================
// NOTIFICATION SETTINGS SCREEN
// lib/screens/settings/notification_settings_screen.dart
//
// Premium fintech settings screen for managing notification preferences.
// Syncs with Firestore in real-time — toggling the switch immediately updates
// the user's `notificationsEnabled` field, which gates FCM push delivery.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_spacing.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final NotificationService _notifService = NotificationService();
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBg,
        title: Text(
          'Notification Settings',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // ── Header illustration ─────────────────────────────────────
            _buildHeaderSection(),

            const SizedBox(height: 24),

            // ── Main toggle ──────────────────────────────────────────────
            _buildMainToggle(user.uid),

            const SizedBox(height: 16),

            // ── Detail cards ─────────────────────────────────────────────
            _buildNotificationDetailCards(),

            const SizedBox(height: 24),

            // ── Info section ─────────────────────────────────────────────
            _buildInfoSection(),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildHeaderSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor.withValues(alpha: 0.08),
            AppTheme.primaryColor.withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: AppTheme.primaryLight,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Push Notifications',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Control how SafePay sends you alerts for incoming payments.',
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.05);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAIN TOGGLE — Real-time synced with Firestore
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildMainToggle(String userId) {
    return StreamBuilder<bool>(
      stream: _notifService.watchNotificationPreference(userId),
      builder: (context, snapshot) {
        final enabled = snapshot.data ?? true;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(
              color: enabled
                  ? AppTheme.secondaryColor.withValues(alpha: 0.25)
                  : AppTheme.darkDivider,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Status icon
                  AnimatedContainer(
                    duration: AppTheme.normal,
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: enabled
                          ? AppTheme.secondaryColor.withValues(alpha: 0.12)
                          : AppTheme.errorColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(
                      enabled
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_off_rounded,
                      color: enabled
                          ? AppTheme.secondaryColor
                          : AppTheme.textMuted,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Label
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Payment Request Notifications',
                          style: GoogleFonts.inter(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            enabled
                                ? 'You\'ll receive alerts for incoming payments'
                                : 'Notifications are paused',
                            key: ValueKey(enabled),
                            style: GoogleFonts.inter(
                              color: enabled
                                  ? AppTheme.textSecondary
                                  : AppTheme.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Switch
                  _isSaving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primaryColor,
                          ),
                        )
                      : Switch.adaptive(
                          value: enabled,
                          onChanged: (val) => _toggleNotifications(userId, val),
                          activeThumbColor: AppTheme.secondaryColor,
                          activeTrackColor:
                              AppTheme.secondaryColor.withValues(alpha: 0.3),
                          inactiveThumbColor: AppTheme.textMuted,
                          inactiveTrackColor: AppTheme.darkOverlay,
                        ),
                ],
              ),

              // ── Status pill ────────────────────────────────────────────
              const SizedBox(height: 14),
              AnimatedContainer(
                duration: AppTheme.normal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: enabled
                      ? AppTheme.secondaryColor.withValues(alpha: 0.06)
                      : AppTheme.errorColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                    color: enabled
                        ? AppTheme.secondaryColor.withValues(alpha: 0.15)
                        : AppTheme.errorColor.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: enabled
                            ? AppTheme.secondaryColor
                            : AppTheme.errorColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      enabled ? 'ACTIVE' : 'DISABLED',
                      style: GoogleFonts.inter(
                        color: enabled
                            ? AppTheme.secondaryColor
                            : AppTheme.errorColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.05);
      },
    );
  }

  Future<void> _toggleNotifications(String userId, bool enabled) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      await _notifService.updateNotificationPreference(
        userId: userId,
        enabled: enabled,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled
                  ? 'Payment notifications enabled'
                  : 'Payment notifications paused',
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
            ),
            backgroundColor:
                enabled ? AppTheme.secondaryColor : AppTheme.darkOverlay,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update preference. Please try again.',
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
            ),
            backgroundColor: AppTheme.errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DETAIL CARDS
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildNotificationDetailCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NOTIFICATION TYPES',
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          const _DetailCard(
            icon: Icons.payment_rounded,
            iconColor: AppTheme.accentOrange,
            title: 'Payment Requests',
            subtitle:
                'When someone wants to send you money — includes ACCEPT/REJECT actions',
            isActive: true,
          ),
          const SizedBox(height: 8),
          const _DetailCard(
            icon: Icons.check_circle_rounded,
            iconColor: AppTheme.secondaryColor,
            title: 'Approval Confirmations',
            subtitle: 'When your payment request is accepted by the receiver',
            isActive: true,
          ),
          const SizedBox(height: 8),
          const _DetailCard(
            icon: Icons.cancel_rounded,
            iconColor: AppTheme.errorColor,
            title: 'Rejections & Refunds',
            subtitle: 'When a payment is rejected and amount is refunded',
            isActive: true,
          ),
          const SizedBox(height: 8),
          const _DetailCard(
            icon: Icons.paid_rounded,
            iconColor: AppTheme.primaryLight,
            title: 'Money Received',
            subtitle: 'Confirmation when funds are credited to your wallet',
            isActive: true,
          ),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.05);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INFO SECTION
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildInfoSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.infoColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppTheme.infoColor.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppTheme.infoColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Important',
                  style: GoogleFonts.inter(
                    color: AppTheme.infoColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Even with notifications disabled, incoming payment requests '
                  'will still appear in your in-app notification centre. '
                  'You can review and respond to them when you open SafePay.',
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 400.ms);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SUPPORTING WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _DetailCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isActive;

  const _DetailCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppTheme.darkDivider),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isActive ? AppTheme.secondaryColor : AppTheme.textDisabled,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
