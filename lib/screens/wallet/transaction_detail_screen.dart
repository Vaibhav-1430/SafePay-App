import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/transaction_model.dart';
import '../../services/auth_service.dart';
import '../../services/transaction_service.dart';
import '../../utils/app_constants.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_theme.dart';

class TransactionDetailScreen extends StatelessWidget {
  final String transactionId;

  const TransactionDetailScreen({
    super.key,
    required this.transactionId,
  });

  Color _statusColor(TransactionStatus status) {
    switch (status) {
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

  Color _riskColor(int score) {
    if (score >= 75) return AppTheme.errorColor;
    if (score >= 40) return AppTheme.warningColor;
    return AppTheme.successColor;
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.read<AuthService>().currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBg,
        title: Text(
          'Transaction Details',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: StreamBuilder<TransactionModel?>(
        stream: context.read<TransactionService>().watchTransaction(transactionId),
        builder: (context, snapshot) {
          final tx = snapshot.data;
          if (tx == null) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            );
          }

          final isSent = tx.senderId == currentUserId;
          final counterpartyName = isSent ? tx.receiverName : tx.senderName;
          final counterpartyUpi = isSent ? tx.receiverUpiId : tx.senderUpiId;
          final riskScore = tx.riskScore ?? 0;
          final riskColor = _riskColor(riskScore);
          final statusColor = _statusColor(tx.status);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppTheme.darkDivider),
                  ),
                  child: Column(
                    children: [
                      Text(
                        isSent ? 'Paid' : 'Received',
                        style: GoogleFonts.inter(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        Formatters.formatCurrency(tx.amount),
                        style: GoogleFonts.inter(
                          color: isSent ? AppTheme.errorColor : AppTheme.successColor,
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                        child: Text(
                          tx.statusLabel,
                          style: GoogleFonts.inter(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppTheme.darkDivider),
                  ),
                  child: Column(
                    children: [
                      _DetailRow(label: 'Name', value: counterpartyName),
                      _divider(),
                      _DetailRow(label: 'UPI ID', value: Formatters.maskUpiId(counterpartyUpi)),
                      _divider(),
                      _DetailRow(label: 'Date & Time', value: Formatters.formatDate(tx.createdAt)),
                      _divider(),
                      _DetailRow(label: 'Transaction ID', value: tx.transactionId),
                      if ((tx.note ?? '').isNotEmpty) ...[
                        _divider(),
                        _DetailRow(label: 'Note', value: tx.note!),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: riskColor.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.shield_outlined, color: riskColor, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Risk Score: $riskScore%',
                            style: GoogleFonts.inter(
                              color: riskColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value: (riskScore / 100).clamp(0, 1).toDouble(),
                          minHeight: 6,
                          color: riskColor,
                          backgroundColor: riskColor.withValues(alpha: 0.12),
                        ),
                      ),
                      if (tx.riskFlags != null && tx.riskFlags!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        ...tx.riskFlags!.take(4).map(
                              (warning) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '• $warning',
                                  style: GoogleFonts.inter(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _divider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Divider(height: 1, color: AppTheme.darkDivider),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
