import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/app_theme.dart';
import '../utils/app_spacing.dart';

/// Reusable trust & security badges for fintech-grade UI.
///
/// These small visual indicators dramatically increase perceived security
/// and professional credibility.

// ── Shield Security Badge (header-level) ──────────────────────────
class SecurityBadge extends StatelessWidget {
  final String label;
  final Color? color;

  const SecurityBadge({
    super.key,
    this.label = 'UPI Secured',
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.successColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: c.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_rounded, size: 12, color: c),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              color: c,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Inline Verified Badge ─────────────────────────────────────────
class VerifiedBadge extends StatelessWidget {
  final String label;
  final double iconSize;
  final double fontSize;

  const VerifiedBadge({
    super.key,
    this.label = 'Verified',
    this.iconSize = 12,
    this.fontSize = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded,
              size: iconSize, color: AppTheme.primaryColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: GoogleFonts.inter(
              color: AppTheme.primaryColor,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Trusted Contact Badge ─────────────────────────────────────────
class TrustedBadge extends StatelessWidget {
  final double iconSize;

  const TrustedBadge({super.key, this.iconSize = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.successColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user_rounded,
              color: AppTheme.successColor, size: iconSize),
          const SizedBox(width: 4),
          Text(
            'Trusted',
            style: GoogleFonts.inter(
              color: AppTheme.successColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Merchant Badge ────────────────────────────────────────────────
class MerchantBadge extends StatelessWidget {
  const MerchantBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.secondaryColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.store_rounded,
              color: AppTheme.secondaryColor, size: 12),
          const SizedBox(width: 4),
          Text(
            'Merchant',
            style: GoogleFonts.inter(
              color: AppTheme.secondaryColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Escrow Protection Banner ──────────────────────────────────────
class EscrowBanner extends StatelessWidget {
  final String? title;
  final String? subtitle;

  const EscrowBanner({
    super.key,
    this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.infoColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppTheme.infoColor.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.infoColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(Icons.account_balance_wallet_rounded,
                color: AppTheme.infoColor, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title ?? 'Protected by SafePay Escrow',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle ??
                      'Funds are held securely until the receiver approves.',
                  style: GoogleFonts.inter(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Encryption Label (for PIN screen) ─────────────────────────────
class EncryptionLabel extends StatelessWidget {
  const EncryptionLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: AppTheme.darkDivider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_rounded,
              size: 12, color: AppTheme.textMuted.withValues(alpha: 0.7)),
          const SizedBox(width: 4),
          Text(
            'End-to-end encrypted',
            style: GoogleFonts.inter(
              color: AppTheme.textMuted.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status Timeline Step ──────────────────────────────────────────
enum TimelineStepState { completed, active, pending }

class StatusTimeline extends StatelessWidget {
  final List<TimelineStep> steps;

  const StatusTimeline({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(steps.length * 2 - 1, (index) {
        if (index.isEven) {
          return steps[index ~/ 2];
        }
        // Connector line
        final prevState = steps[index ~/ 2].state;
        return Container(
          width: 2,
          height: 24,
          margin: const EdgeInsets.only(left: 15),
          decoration: BoxDecoration(
            color: prevState == TimelineStepState.completed
                ? AppTheme.successColor.withValues(alpha: 0.4)
                : AppTheme.darkDivider,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}

class TimelineStep extends StatelessWidget {
  final String label;
  final String? time;
  final TimelineStepState state;

  const TimelineStep({
    super.key,
    required this.label,
    this.time,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      TimelineStepState.completed => AppTheme.successColor,
      TimelineStepState.active    => AppTheme.pendingColor,
      TimelineStepState.pending   => AppTheme.textDisabled,
    };

    final icon = switch (state) {
      TimelineStepState.completed => Icons.check_circle_rounded,
      TimelineStepState.active    => Icons.radio_button_on_rounded,
      TimelineStepState.pending   => Icons.radio_button_off_rounded,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: state == TimelineStepState.completed ? 0.12 : 0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: state == TimelineStepState.pending
                    ? AppTheme.textDisabled
                    : AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (time != null)
            Text(
              time!,
              style: GoogleFonts.inter(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}
