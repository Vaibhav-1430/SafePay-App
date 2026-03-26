import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pinput/pinput.dart';
import 'package:provider/provider.dart';
import '../../models/transaction_model.dart';
import '../../services/auth_service.dart';
import '../../services/transaction_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/trust_badge.dart';

class PinEntryScreen extends StatefulWidget {
  final String transactionId;
  const PinEntryScreen({super.key, required this.transactionId});

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  final _pinController = TextEditingController();
  bool _isProcessing = false;
  bool _hasError = false;
  bool _navigated = false;
  int _requiredPinLength = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final configuredLength = context.read<AuthService>().currentUser?.upiPinLength;
      if (configuredLength == 4 || configuredLength == 6) {
        setState(() => _requiredPinLength = configuredLength!);
      }
    });
  }

  // Clean, premium PIN theme
  final _pinTheme = PinTheme(
    width: 58,
    height: 58,
    textStyle: GoogleFonts.inter(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: AppTheme.textPrimary,
    ),
    decoration: BoxDecoration(
      color: AppTheme.darkCard,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppTheme.darkDivider, width: 1),
    ),
  );

  Future<void> _verifyPin() async {
    if (_isProcessing || _navigated) return;
    if (_pinController.text.length != _requiredPinLength) return;

    // Haptic feedback for interaction
    HapticFeedback.lightImpact();

    setState(() {
      _isProcessing = true;
      _hasError = false;
    });

    final auth = context.read<AuthService>();
    final txService = context.read<TransactionService>();
    final isValid = await auth.verifyUpiPin(_pinController.text);
    if (!mounted) return;

    if (!isValid) {
      HapticFeedback.heavyImpact();
      setState(() {
        _isProcessing = false;
        _hasError = true;
      });
      _pinController.clear();
      AppSnackBar.showError(context, 'Incorrect PIN. Please try again.');
      return;
    }

    // Complete the transaction
    final result = await txService.completePayment(widget.transactionId);
    if (!mounted) return;

    setState(() => _isProcessing = false);
    if (result['success'] == true) {
      HapticFeedback.mediumImpact();
      _navigated = true;
      context.go('/success/${widget.transactionId}');
    } else {
      AppSnackBar.showError(context, result['error'] ?? 'Transaction failed');
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
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

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  // Back button
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.darkCard,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: AppTheme.darkDivider),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new,
                            color: AppTheme.textPrimary, size: 16),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Lock icon — premium double-ring
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
                        child: const Icon(Icons.lock_outline_rounded,
                            color: AppTheme.primaryColor, size: 36),
                      ),
                    ],
                  )
                      .animate()
                      .scale(duration: 500.ms, curve: Curves.easeOut)
                      .fadeIn(),
                  const SizedBox(height: 24),
                  Text(
                    'Enter UPI PIN',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ).animate().fadeIn(delay: 200.ms),
                  const SizedBox(height: 8),
                  if (tx != null)
                    Text(
                      'To send ${Formatters.formatCurrency(tx.amount)} to ${tx.receiverName}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ).animate().fadeIn(delay: 300.ms),
                  const SizedBox(height: 40),
                  // PIN Input
                  Pinput(
                    key: ValueKey('payment-pin-$_requiredPinLength'),
                    controller: _pinController,
                    length: _requiredPinLength,
                    obscureText: true,
                    obscuringCharacter: '●',
                    defaultPinTheme: _pinTheme,
                    focusedPinTheme: _pinTheme.copyWith(
                      decoration: _pinTheme.decoration!.copyWith(
                        border: Border.all(
                          color: _hasError
                              ? AppTheme.errorColor
                              : AppTheme.primaryColor,
                          width: 1.5,
                        ),
                      ),
                    ),
                    submittedPinTheme: _pinTheme.copyWith(
                      decoration: _pinTheme.decoration!.copyWith(
                        color: AppTheme.primaryColor.withValues(alpha: 0.08),
                        border: Border.all(
                            color: AppTheme.primaryColor, width: 1),
                      ),
                    ),
                    errorPinTheme: _pinTheme.copyWith(
                      decoration: _pinTheme.decoration!.copyWith(
                        border: Border.all(
                            color: AppTheme.errorColor, width: 1.5),
                      ),
                    ),
                    onCompleted: (_) => _verifyPin(),
                  ).animate().fadeIn(delay: 400.ms),
                  const SizedBox(height: 16),
                  // Encryption label
                  const EncryptionLabel()
                      .animate()
                      .fadeIn(delay: 450.ms),
                  const SizedBox(height: 40),
                  // Submit button
                  PrimaryButton(
                    label: 'Confirm Payment',
                    onPressed: _isProcessing ? null : _verifyPin,
                    isLoading: _isProcessing,
                    icon: Icons.check_circle_outline_rounded,
                  ).animate().fadeIn(delay: 500.ms),
                  const SizedBox(height: 16),
                  // Transaction amount card
                  if (tx != null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                            color: AppTheme.secondaryColor.withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: const Icon(Icons.arrow_upward_rounded,
                                color: AppTheme.secondaryColor, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Transferring',
                            style: GoogleFonts.inter(
                              color: AppTheme.textMuted,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            Formatters.formatCurrency(tx.amount),
                            style: GoogleFonts.inter(
                              color: AppTheme.secondaryColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              fontFeatures: [
                                const FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 600.ms),
                  const Spacer(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
