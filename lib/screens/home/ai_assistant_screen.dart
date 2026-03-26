import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../services/ai_security_service.dart';
import '../../services/auth_service.dart';
import '../../services/transaction_service.dart';
import '../../utils/app_theme.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final _questionController = TextEditingController();
  final _ai = AiSecurityService();

  bool _loading = false;
  String? _answer;
  Map<String, double> _breakdown = const {};
  double _total = 0;
  String? _topCategory;

  Widget _assistantSkeleton() {
    return Column(
      children: List.generate(
        2,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Shimmer.fromColors(
            baseColor: AppTheme.darkCard,
            highlightColor: AppTheme.darkDivider,
            child: Container(
              height: 88,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _askQuestion([String? quickQuestion]) async {
    final auth = context.read<AuthService>();
    final userId = auth.currentUser?.uid;
    if (userId == null) return;

    final question = (quickQuestion ?? _questionController.text).trim();
    if (question.isEmpty) return;

    setState(() => _loading = true);

    try {
      final txService = context.read<TransactionService>();
      final txs = await txService.getUserTransactionsForCurrentMonth(userId);
      final result = await _ai.assistantSummary(
        userId: userId,
        question: question,
        transactions: txs,
      );

      if (!mounted) return;
      setState(() {
        _answer = result?.answer ??
            'I could not connect to the assistant service. Showing limited local insight.';
        _breakdown = result?.categoryBreakdown ?? const {};
        _total = result?.monthlyTotal ?? 0;
        _topCategory = result?.topCategory;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _answer = 'Assistant failed to load. Please try again.';
        _breakdown = const {};
        _total = 0;
        _topCategory = null;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBg,
        title: const Text('AI Financial Assistant'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: AppTheme.darkCard,
                border: Border.all(color: AppTheme.darkDivider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ask about your spending',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _questionController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'How much did I spend this month?',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _loading ? null : () => _askQuestion(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      'How much did I spend this month?',
                      'Where did most of my money go?',
                      'Summarize my monthly spending',
                    ]
                        .map(
                          (q) => ActionChip(
                            label: Text(q),
                            onPressed: _loading ? null : () => _askQuestion(q),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_loading) ...[
              const SizedBox(height: 10),
              _assistantSkeleton(),
            ],
            const SizedBox(height: 10),
            if (_answer != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: AppTheme.darkCard,
                  border: Border.all(color: AppTheme.darkDivider),
                ),
                child: Text(
                  _answer!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            if (_answer != null) const SizedBox(height: 10),
            if (_answer != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: AppTheme.darkCard,
                  border: Border.all(color: AppTheme.darkDivider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Monthly Total: ₹${_total.toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.white)),
                    const SizedBox(height: 6),
                    Text('Top Category: ${_topCategory ?? 'N/A'}',
                        style: const TextStyle(color: AppTheme.textSecondary)),
                    const SizedBox(height: 10),
                    ..._breakdown.entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.key,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                            Text(
                              '₹${e.value.toStringAsFixed(0)}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
