import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../models/transaction_model.dart';
import '../../services/auth_service.dart';
import '../../services/transaction_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_constants.dart';
import '../../widgets/transaction_tile.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<TransactionModel> _transactions = [];

  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final auth = context.read<AuthService>();
    final userId = auth.currentUser?.uid;
    if (userId == null) return;

    final page = await context.read<TransactionService>().getTransactionsPage(
          userId: userId,
          limit: 20,
        );

    if (!mounted) return;
    setState(() {
      _transactions
        ..clear()
        ..addAll(page.items);
      _lastDoc = page.lastDoc;
      _hasMore = page.hasMore;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final auth = context.read<AuthService>();
    final userId = auth.currentUser?.uid;
    if (userId == null) return;

    setState(() => _loadingMore = true);
    final page = await context.read<TransactionService>().getTransactionsPage(
          userId: userId,
          startAfter: _lastDoc,
          limit: 20,
        );
    if (!mounted) return;

    setState(() {
      _transactions.addAll(page.items);
      _lastDoc = page.lastDoc;
      _hasMore = page.hasMore;
      _loadingMore = false;
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Widget _buildSkeletonList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: AppTheme.darkCard,
        highlightColor: AppTheme.darkOverlay,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 80,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    width: 60,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 44,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemCount: 8,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final userId = auth.currentUser!.uid;

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBg,
        title: Text('Transaction History',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loading
          ? _buildSkeletonList()
          : _transactions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.receipt_long_outlined,
                          size: 64, color: AppTheme.textDisabled),
                      const SizedBox(height: 20),
                      Text(
                        'No transactions yet',
                        style: GoogleFonts.inter(
                          color: AppTheme.textMuted,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your payment history will appear here',
                        style: GoogleFonts.inter(
                          color: AppTheme.textDisabled,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : Builder(
                  builder: (context) {
                    final grouped = <String, List<TransactionModel>>{};
                    for (final tx in _transactions) {
                      final date = Formatters.formatShortDate(tx.createdAt);
                      grouped.putIfAbsent(date, () => []).add(tx);
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount:
                          grouped.keys.length + (_loadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= grouped.keys.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppTheme.primaryColor,
                                strokeWidth: 2,
                              ),
                            ),
                          );
                        }

                        final date = grouped.keys.elementAt(index);
                        final txs = grouped[date]!;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14, horizontal: 4),
                              child: Row(
                                children: [
                                  Container(
                                    width: 2,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor,
                                      borderRadius:
                                          BorderRadius.circular(1),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    date.toUpperCase(),
                                    style: GoogleFonts.inter(
                                      color: AppTheme.textMuted,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: AppTheme.darkCard,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.md),
                                border: Border.all(
                                    color: AppTheme.darkDivider),
                              ),
                              child: Column(
                                children:
                                    txs.asMap().entries.map((entry) {
                                  final i = entry.key;
                                  final tx = entry.value;
                                  return Column(
                                    children: [
                                      TransactionTile(
                                        transaction: tx,
                                        currentUserId: userId,
                                        onTap: () => context.push(
                                          '/transaction/${tx.transactionId}',
                                        ),
                                      ),
                                      if (i < txs.length - 1)
                                        const Divider(
                                          color: AppTheme.darkDivider,
                                          height: 1,
                                          indent: 70,
                                        ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ).animate()
                                .fadeIn(delay: (index * 70).ms)
                                .slideX(begin: 0.02, duration: 200.ms),
                            const SizedBox(height: 8),
                          ],
                        );
                      },
                    );
                  },
                ),
    );
  }
}
