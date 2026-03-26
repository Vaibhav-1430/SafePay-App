import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/transaction_model.dart';
import '../utils/app_theme.dart';
import '../utils/app_spacing.dart';
import '../utils/app_constants.dart';

/// Redesigned transaction tile — Google Pay-quality, scannable, fintech-grade.
class TransactionTile extends StatelessWidget {
  final TransactionModel transaction;
  final String currentUserId;
  final VoidCallback? onTap;

  const TransactionTile({
    super.key,
    required this.transaction,
    required this.currentUserId,
    this.onTap,
  });

  bool get isSent => transaction.senderId == currentUserId;

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();
    final sign = isSent ? '-' : '+';
    final signColor = isSent ? AppTheme.errorColor : AppTheme.successColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Avatar
              _TransactionAvatar(
                name: isSent ? transaction.receiverName : transaction.senderName,
                isSent: isSent,
                type: transaction.type,
              ),
              const SizedBox(width: 14),
              // Name + time + note
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSent ? transaction.receiverName : transaction.senderName,
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          Formatters.formatRelativeTime(transaction.createdAt),
                          style: GoogleFonts.inter(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        if (transaction.note != null &&
                            transaction.note!.isNotEmpty) ...[
                          Container(
                            width: 3,
                            height: 3,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: const BoxDecoration(
                              color: AppTheme.textDisabled,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              transaction.note!,
                              style: GoogleFonts.inter(
                                color: AppTheme.textMuted,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Amount + status
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$sign${Formatters.formatCurrency(transaction.amount)}',
                    style: GoogleFonts.inter(
                      color: signColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      fontFeatures: [const FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 4),
                  _StatusBadge(
                    status: transaction.status,
                    color: statusColor,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (transaction.status) {
      case TransactionStatus.completed:
        return AppTheme.successColor;
      case TransactionStatus.pending:
        return AppTheme.pendingColor;
      case TransactionStatus.approved:
        return AppTheme.infoColor;
      case TransactionStatus.rejected:
        return AppTheme.errorColor;
      case TransactionStatus.refunded:
        return AppTheme.warningColor;
      case TransactionStatus.timedOut:
        return AppTheme.textMuted;
    }
  }
}

// ── Transaction Avatar with directional indicator ─────────────────
class _TransactionAvatar extends StatelessWidget {
  final String name;
  final bool isSent;
  final TransactionType type;

  const _TransactionAvatar({
    required this.name,
    required this.isSent,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final color = type == TransactionType.topUp
        ? AppTheme.successColor
        : isSent
            ? AppTheme.errorColor
            : AppTheme.successColor;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Stack(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              initial,
              style: GoogleFonts.inter(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ),
        ),
        // Directional indicator
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: AppTheme.darkBg,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.darkCard, width: 2),
            ),
            child: Icon(
              type == TransactionType.topUp
                  ? Icons.add_rounded
                  : isSent
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
              color: color,
              size: 10,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final TransactionStatus status;
  final Color color;

  const _StatusBadge({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        _label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  String get _label {
    switch (status) {
      case TransactionStatus.completed:
        return 'DONE';
      case TransactionStatus.pending:
        return 'PENDING';
      case TransactionStatus.approved:
        return 'APPROVED';
      case TransactionStatus.rejected:
        return 'REJECTED';
      case TransactionStatus.refunded:
        return 'REFUNDED';
      case TransactionStatus.timedOut:
        return 'EXPIRED';
    }
  }
}
