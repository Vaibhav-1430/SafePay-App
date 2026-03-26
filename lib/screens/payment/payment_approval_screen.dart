// =============================================================================
// PAYMENT APPROVAL SCREEN — REDESIGNED
// lib/screens/payment/payment_approval_screen.dart
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/transaction_model.dart';
import '../../services/auth_service.dart';
import '../../services/contacts_service.dart';
import '../../services/transaction_service.dart';
import '../../services/ai_security_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/trust_badge.dart';

class PaymentApprovalScreen extends StatefulWidget {
  final String transactionId;
  const PaymentApprovalScreen({super.key, required this.transactionId});

  @override
  State<PaymentApprovalScreen> createState() => _PaymentApprovalScreenState();
}

class _PaymentApprovalScreenState extends State<PaymentApprovalScreen> {
  bool _isProcessing = false;
  bool _navigated = false;
  bool _riskExpanded = false;
  bool _addToTrustedContacts = false;
  final AiSecurityService _aiSecurityService = AiSecurityService();
  String? _scamWarning;
  double? _scamProbability;
  String? _checkedScamForTxId;

  void _navigateOnce(String route) {
    if (_navigated || !mounted) return;
    _navigated = true;
    context.go(route);
  }

  Future<void> _approve(TransactionModel tx) async {
    if (_isProcessing || _navigated) return;
    HapticFeedback.mediumImpact();
    setState(() => _isProcessing = true);

    // Capture service references BEFORE any async gap
    final txService = context.read<TransactionService>();
    final auth = context.read<AuthService>();
    final contacts = context.read<ContactsService>();

    final result = await txService.approvePayment(
          widget.transactionId,
          addToTrustedContacts: _addToTrustedContacts,
        );
    if (!mounted) return;

    if (result['success'] == true && _addToTrustedContacts) {
      final sender = await auth.getUserById(tx.senderId);
      if (!mounted) return;
      if (sender != null && auth.currentUser != null) {
        await contacts.addTrustedContact(
          ownerUserId: auth.currentUser!.uid,
          contact: sender,
        );
        if (!mounted) return;
      }
    }

    setState(() => _isProcessing = false);
    if (result['success'] == true) {
      AppSnackBar.showSuccess(context, 'Payment approved successfully.');
      _navigateOnce('/home');
    } else {
      AppSnackBar.showError(context, result['error'] ?? 'Failed to approve');
    }
  }

  Future<void> _reject() async {
    // Capture service ref before async gap
    final txService = context.read<TransactionService>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl)),
        title: Text('Reject Payment?',
            style: GoogleFonts.inter(
                color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
        content: Text(
          'The payment will be cancelled and the amount will be refunded to the sender.',
          style: GoogleFonts.inter(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject',
                style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      HapticFeedback.heavyImpact();
      setState(() => _isProcessing = true);
      await txService.rejectPayment(widget.transactionId);
      if (mounted) {
        _navigateOnce('/home');
      }
    }
  }

  Color _riskColor(String? riskLevel) {
    switch (riskLevel?.toLowerCase()) {
      case 'high risk':
        return AppTheme.errorColor;
      case 'medium risk':
        return AppTheme.warningColor;
      default:
        return AppTheme.successColor;
    }
  }

  IconData _riskIcon(String? riskLevel) {
    switch (riskLevel?.toLowerCase()) {
      case 'high risk':
        return Icons.warning_rounded;
      case 'medium risk':
        return Icons.info_rounded;
      default:
        return Icons.shield_rounded;
    }
  }

  Future<void> _checkScamMessage(TransactionModel tx) async {
    final note = tx.note?.trim();
    if (note == null || note.isEmpty) return;
    if (_checkedScamForTxId == tx.transactionId) return;

    _checkedScamForTxId = tx.transactionId;
    final result = await _aiSecurityService.detectScamMessage(note);
    if (!mounted || result == null) return;

    if (result.isScam || result.scamProbability >= 0.6) {
      setState(() {
        _scamWarning = result.warning;
        _scamProbability = result.scamProbability;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: StreamBuilder<TransactionModel?>(
        stream: context
            .read<TransactionService>()
            .watchTransaction(widget.transactionId),
        builder: (context, snapshot) {
          final tx = snapshot.data;
          if (tx == null) {
            return const Center(
              child: CircularProgressIndicator(
                  color: AppTheme.primaryColor, strokeWidth: 2),
            );
          }

          // Auto-navigate on status change
          if (!_navigated &&
              (tx.status == TransactionStatus.completed ||
               tx.status == TransactionStatus.rejected ||
               tx.status == TransactionStatus.timedOut)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (tx.status == TransactionStatus.completed) {
                _navigateOnce('/success/${widget.transactionId}');
                return;
              }
              _navigateOnce('/home');
            });
          }

          final riskLevel = tx.riskLevel;
          final riskScore = tx.riskScore;
          final riskFlags = tx.riskFlags;
          final riskColor = _riskColor(riskLevel);

          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkScamMessage(tx);
          });

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 12),
                  // Top handle
                  Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.darkDivider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // ── Incoming Payment Icon ───────────────────────────
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer ring
                      Container(
                        width: 110,
                        height: 110,
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
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryColor.withValues(alpha: 0.15),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.arrow_downward_rounded,
                            color: Colors.white, size: 40),
                      ),
                    ],
                  )
                      .animate()
                      .scale(duration: 600.ms, curve: Curves.elasticOut)
                      .fadeIn(),
                  const SizedBox(height: 28),

                  Text(
                    '${tx.senderName} is sending you',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: AppTheme.textSecondary,
                    ),
                  ).animate().fadeIn(delay: 200.ms),
                  const SizedBox(height: 8),
                  Text(
                    Formatters.formatCurrency(tx.amount),
                    style: GoogleFonts.inter(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                      letterSpacing: -1.5,
                    ),
                  ).animate().fadeIn(delay: 300.ms).scale(
                        begin: const Offset(0.8, 0.8),
                        end: const Offset(1.0, 1.0),
                      ),
                  if (tx.note != null && tx.note!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '"${tx.note}"',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppTheme.textMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    ).animate().fadeIn(delay: 400.ms),
                  ],
                  const SizedBox(height: 24),

                  // ── AI Risk Score Badge ──────────────────────────────
                  if (riskLevel != null) ...[
                    GestureDetector(
                      onTap: () =>
                          setState(() => _riskExpanded = !_riskExpanded),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: riskColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(
                              color: riskColor.withValues(alpha: 0.25), width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(_riskIcon(riskLevel),
                                    color: riskColor, size: 18),
                                const SizedBox(width: 10),
                                Text(
                                  'AI Risk Assessment',
                                  style: GoogleFonts.inter(
                                    color: riskColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: riskColor.withValues(alpha: 0.15),
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.full),
                                  ),
                                  child: Text(
                                    riskLevel,
                                    style: GoogleFonts.inter(
                                      color: riskColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  _riskExpanded
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  color: riskColor,
                                  size: 18,
                                ),
                              ],
                            ),
                            if (riskScore != null) ...[
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: riskScore / 100,
                                  color: riskColor,
                                  backgroundColor:
                                      riskColor.withValues(alpha: 0.10),
                                  minHeight: 4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Score: $riskScore/100',
                                style: GoogleFonts.inter(
                                  color: riskColor.withValues(alpha: 0.7),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                            if (_riskExpanded &&
                                riskFlags != null &&
                                riskFlags.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              ...riskFlags.map((flag) => Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.chevron_right,
                                            color:
                                                riskColor.withValues(alpha: 0.6),
                                            size: 14),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            flag,
                                            style: GoogleFonts.inter(
                                              color:
                                                  riskColor.withValues(alpha: 0.8),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )),
                            ],
                          ],
                        ),
                      ),
                    ).animate().fadeIn(delay: 450.ms),
                    const SizedBox(height: 16),
                  ],

                  // ── Scam Warning ────────────────────────────────────
                  if (_scamWarning != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.errorColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(
                          color: AppTheme.errorColor.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: AppTheme.errorColor, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Scam Message Alert',
                                style: GoogleFonts.inter(
                                  color: AppTheme.errorColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _scamWarning!,
                            style: GoogleFonts.inter(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          if (_scamProbability != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Scam probability: ${(_scamProbability! * 100).toStringAsFixed(0)}%',
                              style: GoogleFonts.inter(
                                color: AppTheme.errorColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Sender details card ─────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppTheme.darkDivider),
                    ),
                    child: Row(
                      children: [
                         Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            color: AppTheme.primaryColor,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              tx.senderName.isNotEmpty
                                  ? tx.senderName[0].toUpperCase()
                                  : '?',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tx.senderName,
                                style: GoogleFonts.inter(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                Formatters.maskUpiId(tx.senderUpiId),
                                style: GoogleFonts.inter(
                                  color: AppTheme.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_rounded,
                            color: AppTheme.textDisabled, size: 20),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.secondaryColor.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            'YOU',
                            style: GoogleFonts.inter(
                              color: AppTheme.secondaryColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 500.ms),
                  const SizedBox(height: 16),

                  // ── Escrow Info Banner ──────────────────────────────
                  const EscrowBanner(
                    title: 'Escrow Protected',
                    subtitle:
                        'By accepting, money will be transferred after sender enters their UPI PIN.',
                  ).animate().fadeIn(delay: 600.ms),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppTheme.primaryColor,
                      checkColor: Colors.white,
                      value: _addToTrustedContacts,
                      onChanged: _isProcessing
                          ? null
                          : (value) {
                              setState(() {
                                _addToTrustedContacts = value ?? false;
                              });
                            },
                      title: Text(
                        'Add sender to trusted contacts',
                        style: GoogleFonts.inter(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Action Buttons ─────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isProcessing ? null : _reject,
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('Reject'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.errorColor,
                            side: const BorderSide(
                                color: AppTheme.errorColor, width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md),
                            ),
                            textStyle: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : () => _approve(tx),
                          icon: _isProcessing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_rounded, size: 18),
                          label: Text(
                              _isProcessing ? 'Processing...' : 'Accept'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.successColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md),
                            ),
                            textStyle: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 700.ms).slideY(begin: 0.1),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
