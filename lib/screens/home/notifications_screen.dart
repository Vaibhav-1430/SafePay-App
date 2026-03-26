import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_constants.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final userId = auth.currentUser!.uid;

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBg,
        title: const Text('Notifications'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // Mark all as read
              final batch = FirebaseFirestore.instance.batch();
              final unread = await FirebaseFirestore.instance
                  .collection('notifications')
                  .where('userId', isEqualTo: userId)
                  .where('isRead', isEqualTo: false)
                  .get();
              for (final doc in unread.docs) {
                batch.update(doc.reference, {'isRead': true});
              }
              await batch.commit();
            },
            child: const Text('Mark all read',
                style: TextStyle(color: AppTheme.primaryColor, fontSize: 12)),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: userId)
            .orderBy('createdAt', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_outlined,
                      size: 80, color: Colors.white.withValues(alpha: 0.15)),
                  const SizedBox(height: 20),
                  Text(
                    'No notifications yet',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final isRead = data['isRead'] ?? false;
              final type = data['type'] ?? '';
              final createdAt =
                  (data['createdAt'] as Timestamp?)?.toDate();
              final txId = data['data']?['transactionId'];

              return GestureDetector(
                onTap: () async {
                  // Mark as read
                  await docs[index].reference.update({'isRead': true});
                  if (txId != null && context.mounted) {
                    if (type == 'payment_request') {
                      context.push('/payment-approval/$txId');
                    } else if (type == 'payment_approved') {
                      context.push('/pin-entry/$txId');
                    }
                  }
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isRead
                        ? AppTheme.darkCard
                        : AppTheme.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isRead
                          ? AppTheme.darkDivider
                          : AppTheme.primaryColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _notifColor(type).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_notifIcon(type),
                            color: _notifColor(type), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['title'] ?? '',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: isRead
                                    ? FontWeight.w400
                                    : FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              data['body'] ?? '',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                            if (createdAt != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                Formatters.formatRelativeTime(createdAt),
                                style: const TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppTheme.primaryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ).animate().fadeIn(delay: (index * 50).ms),
              );
            },
          );
        },
      ),
    );
  }

  IconData _notifIcon(String type) {
    switch (type) {
      case 'payment_request':
        return Icons.payment_rounded;
      case 'payment_approved':
        return Icons.check_circle_rounded;
      case 'payment_rejected':
        return Icons.cancel_rounded;
      case 'payment_completed':
        return Icons.paid_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _notifColor(String type) {
    switch (type) {
      case 'payment_request':
        return AppTheme.accentOrange;
      case 'payment_approved':
        return AppTheme.successColor;
      case 'payment_rejected':
        return AppTheme.errorColor;
      case 'payment_completed':
        return AppTheme.secondaryColor;
      default:
        return AppTheme.primaryColor;
    }
  }
}
