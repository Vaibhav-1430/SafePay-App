import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/wallet_service.dart';
import '../../widgets/common_widgets.dart';

class TopUpScreen extends StatefulWidget {
  const TopUpScreen({super.key});

  @override
  State<TopUpScreen> createState() => _TopUpScreenState();
}

class _TopUpScreenState extends State<TopUpScreen> {
  final _amountController = TextEditingController();
  bool _isLoading = false;
  int _selectedAmount = 0;

  final _quickAmounts = [500, 1000, 2000, 5000, 10000];

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _topUp() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      AppSnackBar.showError(context, 'Please enter a valid amount');
      return;
    }
    if (amount > 50000) {
      AppSnackBar.showError(context, 'Maximum top-up amount is ₹50,000');
      return;
    }

    setState(() => _isLoading = true);

    final auth = context.read<AuthService>();
    final walletService = context.read<WalletService>();
    final error =
        await walletService.topUp(userId: auth.currentUser!.uid, amount: amount);

    if (mounted) {
      setState(() => _isLoading = false);
      if (error == null) {
        AppSnackBar.showSuccess(
            context, '${Formatters.formatCurrency(amount)} added successfully!');
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) context.pop();
        });
      } else {
        AppSnackBar.showError(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBg,
        title: const Text('Add Money'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current balance
            StreamBuilder(
              stream: context
                  .read<WalletService>()
                  .watchWallet(context.read<AuthService>().currentUser!.uid),
              builder: (context, snapshot) {
                final balance = snapshot.data?.balance ?? 0.0;
                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.10)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_rounded,
                          color: AppTheme.primaryColor, size: 28),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Current Balance',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            Formatters.formatCurrency(balance),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 22,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ).animate().fadeIn(),
            const SizedBox(height: 32),
            const Text(
              'Select Amount',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ).animate().fadeIn(delay: 100.ms),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              childAspectRatio: 2.5,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: _quickAmounts.map((amt) {
                final isSelected = _selectedAmount == amt;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedAmount = amt;
                      _amountController.text = amt.toString();
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryColor
                            : AppTheme.darkDivider,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '₹$amt',
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 20),
            const Text(
              'Or Enter Custom Amount',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ).animate().fadeIn(delay: 300.ms),
            const SizedBox(height: 8),
            AppTextField(
              controller: _amountController,
              label: 'Amount',
              hint: '₹ 100 - 50,000',
              keyboardType: TextInputType.number,
              prefixIcon: Icons.currency_rupee_rounded,
              onChanged: (_) => setState(() => _selectedAmount = 0),
            ).animate().fadeIn(delay: 350.ms),
            const SizedBox(height: 32),
            // Simulated payment methods
            const Text(
              'Payment Method',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ).animate().fadeIn(delay: 400.ms),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.account_balance_rounded,
                        color: AppTheme.primaryColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Simulated Bank Transfer',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Instantly adds to wallet (prototype mode)',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.radio_button_checked_rounded,
                      color: AppTheme.primaryColor),
                ],
              ),
            ).animate().fadeIn(delay: 450.ms),
            const SizedBox(height: 32),
            PrimaryButton(
              label: 'Add Money',
              onPressed: _topUp,
              isLoading: _isLoading,
              icon: Icons.add_rounded,
              gradient: const LinearGradient(
                colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
              ),
            ).animate().fadeIn(delay: 500.ms),
          ],
        ),
      ),
    );
  }
}
