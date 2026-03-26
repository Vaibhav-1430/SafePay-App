import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/transaction_model.dart';
import '../models/user_model.dart';
import 'wallet_service.dart';
import 'notification_service.dart';
import 'fraud_risk_engine.dart';
import 'ai_security_service.dart';
import 'api_service.dart';

class PaginatedTransactions {
  final List<TransactionModel> items;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;
  final bool hasMore;

  const PaginatedTransactions({
    required this.items,
    required this.lastDoc,
    required this.hasMore,
  });
}

class TransactionService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-south1');
  final WalletService _walletService = WalletService();
  final NotificationService _notificationService = NotificationService();
  final FraudRiskEngine _riskEngine = FraudRiskEngine();
  final AiSecurityService _aiSecurityService = AiSecurityService();
  final ApiService _api = ApiService();

  // Escrow timeout duration (5 minutes for prototype)
  static const Duration _escrowTimeout = Duration(minutes: 5);
  final Map<String, List<TransactionModel>> _recentTxCache = {};
  final Map<String, DateTime> _recentTxCacheUpdatedAt = {};
  static const Duration _recentTxCacheTtl = Duration(seconds: 25);

  bool _isRecentCacheValid(String userId) {
    final ts = _recentTxCacheUpdatedAt[userId];
    if (ts == null) return false;
    return DateTime.now().difference(ts) < _recentTxCacheTtl;
  }

  void _cacheRecent(String userId, List<TransactionModel> items) {
    _recentTxCache[userId] = List<TransactionModel>.from(items);
    _recentTxCacheUpdatedAt[userId] = DateTime.now();
  }

  void _invalidateUserCaches(String userId) {
    _recentTxCache.remove(userId);
    _recentTxCacheUpdatedAt.remove(userId);
  }

  /// Initiate a payment (moves to escrow)
  Future<Map<String, dynamic>> initiatePayment({
    required UserModel sender,
    required UserModel receiver,
    required double amount,
    String? note,
    int delayMinutes = 0,
    bool isTrustedContact = false,
    bool isMerchantFastMode = false,
    bool verifiedHighRisk = false,
  }) async {
    try {
      debugPrint(
        '[TransactionService] Creating transaction... sender=${sender.uid}, receiver=${receiver.uid}, amount=$amount, delayMinutes=$delayMinutes, trusted=$isTrustedContact, merchantFast=$isMerchantFastMode',
      );

      final authUid = FirebaseAuth.instance.currentUser?.uid;
      if (authUid == null) {
        debugPrint(
            '[TransactionService] Auth check failed: no current Firebase user');
        return {'success': false, 'error': 'Authentication required'};
      }
      if (authUid != sender.uid) {
        debugPrint(
            '[TransactionService] Auth UID mismatch. authUid=$authUid senderId=${sender.uid}');
        return {
          'success': false,
          'error': 'Authentication mismatch. Please sign in again.'
        };
      }
      if (amount <= 0) {
        debugPrint('[TransactionService] Invalid amount: $amount');
        return {'success': false, 'error': 'Invalid amount'};
      }
      if (sender.uid == receiver.uid) {
        debugPrint(
            '[TransactionService] Self-transfer blocked for uid=${sender.uid}');
        return {'success': false, 'error': 'Cannot send money to yourself'};
      }

      debugPrint(
          '[TransactionService] Receiver found? true (receiverId=${receiver.uid}, receiverUpi=${receiver.upiId})');

      final senderWallet = await _walletService.getWallet(sender.uid);
      if (senderWallet == null || senderWallet.balance < amount) {
        debugPrint(
            '[TransactionService] Insufficient balance. sender=${sender.uid}, available=${senderWallet?.balance ?? 0}, required=$amount');
        return {'success': false, 'error': 'Insufficient balance'};
      }

      final senderBalanceBefore = senderWallet.balance;
      debugPrint(
          '[TransactionService] Sender balance before: $senderBalanceBefore, after (expected): ${senderBalanceBefore - amount}');

      final now = DateTime.now();
      final expiresAt = now.add(_escrowTimeout);
      final normalizedDelayMinutes = delayMinutes.clamp(0, 60);
      var isInstant = (isTrustedContact || isMerchantFastMode) &&
          normalizedDelayMinutes == 0;

      final historicalAmounts = await _getSenderHistoricalAmounts(sender.uid);
      final txCountLast24h = await _countSenderTransactionsLast24h(sender.uid);
      final avgAmount = historicalAmounts.isEmpty
          ? amount
          : (historicalAmounts.reduce((a, b) => a + b) /
              historicalAmounts.length);
      final unusualSpendingPattern =
          historicalAmounts.length >= 3 && amount > (avgAmount * 2.5);

      const locationMismatch = false;
      const deviceMismatch = false;

      final localRisk = await _riskEngine.analyze(
        senderId: sender.uid,
        receiverId: receiver.uid,
        amount: amount,
        isTrustedContact: isTrustedContact,
      );

      final aiRisk = await _aiSecurityService.assessTransactionRisk(
        userId: sender.uid,
        receiverId: receiver.uid,
        amount: amount,
        knownReceiver: isTrustedContact,
        txCountLast24h: txCountLast24h,
        deviceMismatch: deviceMismatch,
        locationMismatch: locationMismatch,
        unusualSpendingPattern: unusualSpendingPattern,
        historicalAmounts: historicalAmounts,
      );

      final backendRisk = await _verifyPaymentWithBackend(
        senderId: sender.uid,
        receiverId: receiver.uid,
        amount: amount,
        isTrustedContact: isTrustedContact,
        txCountLast24h: txCountLast24h,
        unusualSpendingPattern: unusualSpendingPattern,
        historicalAmounts: historicalAmounts,
      );

      final behavior = await _aiSecurityService.analyzeBehavior(
        userId: sender.uid,
        receiverId: receiver.uid,
        amount: amount,
        knownReceiver: isTrustedContact,
        txCountLast24h: txCountLast24h,
        deviceMismatch: deviceMismatch,
        locationMismatch: locationMismatch,
        unusualSpendingPattern: unusualSpendingPattern,
      );

      var finalRiskScore = localRisk.score / 100.0;
      final riskFlags = <String>{...localRisk.flags};

      if (aiRisk != null) {
        finalRiskScore = (finalRiskScore * 0.35) + (aiRisk.riskScore * 0.65);
        riskFlags.addAll(aiRisk.triggers);
      }

      if (backendRisk != null) {
        final backendScore = ((backendRisk['risk_score'] as num?)?.toDouble() ??
                (backendRisk['riskScore'] as num?)?.toDouble() ??
                0)
            .clamp(0.0, 1.0);
        finalRiskScore = (finalRiskScore * 0.7) + (backendScore * 0.3);
        final backendTriggers =
            ((backendRisk['triggers'] as List<dynamic>?) ?? [])
                .map((e) => e.toString())
                .toList();
        riskFlags.addAll(backendTriggers);
      }

      if (behavior != null && behavior.isAnomaly) {
        finalRiskScore = (finalRiskScore + 0.15).clamp(0.0, 1.0);
        riskFlags.addAll(behavior.reasons);
      }

      finalRiskScore = finalRiskScore.clamp(0.0, 1.0);
      final finalRiskScoreInt = (finalRiskScore * 100).round();

      RiskLevel finalRiskLevel;
      String finalRiskLabel;
      if (finalRiskScore >= 0.75) {
        finalRiskLevel = RiskLevel.high;
        finalRiskLabel = 'High Risk';
      } else if (finalRiskScore >= 0.4) {
        finalRiskLevel = RiskLevel.medium;
        finalRiskLabel = 'Medium Risk';
      } else {
        finalRiskLevel = RiskLevel.low;
        finalRiskLabel = 'Low Risk';
      }

      final requireExtraVerification = finalRiskLevel == RiskLevel.high ||
          (aiRisk?.requireExtraVerification ?? false) ||
          (behavior?.action == 'trigger_verification');
      final delayRecommended = (aiRisk?.delayRecommended ?? false) ||
          (finalRiskLevel == RiskLevel.high && amount >= 7000);

      debugPrint(
        '[TransactionService] Risk decision: score=$finalRiskScoreInt, level=$finalRiskLabel, requireExtraVerification=$requireExtraVerification, delayRecommended=$delayRecommended, flags=${riskFlags.toList()}',
      );

      if (requireExtraVerification && !verifiedHighRisk) {
        debugPrint(
            '[TransactionService] High-risk verification required before continuing');
        return {
          'success': false,
          'requiresVerification': true,
          'riskLevel': finalRiskLabel,
          'riskScore': finalRiskScoreInt,
          'riskFlags': riskFlags.toList(),
          'delayRecommended': delayRecommended,
          'error':
              'High-risk transaction detected. Complete additional verification to continue.',
        };
      }

      if (requireExtraVerification) {
        isInstant = false;
      }

      if (isInstant) {
        debugPrint(
            '[TransactionService] Instant settlement downgraded to escrow pending for backend-controlled settlement safety.');
        isInstant = false;
      }

      final risk = RiskAssessment(
        score: finalRiskScoreInt,
        level: finalRiskLevel,
        flags: riskFlags.toList(),
      );

      final txPayload = {
        'senderId': sender.uid,
        'receiverId': receiver.uid,
        'senderName': sender.displayName,
        'receiverName': receiver.displayName,
        'senderUpiId': sender.upiId,
        'receiverUpiId': receiver.upiId,
        'amount': amount,
        'status': isInstant ? 'completed' : 'pending',
        'type': 'send',
        'note': note,
        'createdAt': Timestamp.fromDate(now),
        'completedAt': isInstant ? Timestamp.fromDate(now) : null,
        'expiresAt': isInstant ? null : Timestamp.fromDate(expiresAt),
        'isEscrow': !isInstant,
        'delayMinutes': normalizedDelayMinutes,
        'releaseAfter': normalizedDelayMinutes > 0
            ? Timestamp.fromDate(
                now.add(Duration(minutes: normalizedDelayMinutes)))
            : null,
        'cancelUntil': Timestamp.fromDate(now.add(const Duration(seconds: 90))),
        'isTrustedContact': isTrustedContact,
        'riskScore': risk.score,
        'riskLevel': finalRiskLabel,
        'riskFlags': risk.flags,
        'riskSource': aiRisk == null ? 'local' : 'hybrid_ai',
        'requiresExtraVerification': requireExtraVerification,
        'delayRecommended': delayRecommended,
        'behaviorAnomalyScore': behavior?.anomalyScore,
        'behaviorAnomaly': behavior?.isAnomaly ?? false,
      };

      final txRef = _firestore.collection('transactions').doc();
      final txId = txRef.id;
      final senderWalletRef = _firestore.collection('wallets').doc(sender.uid);

      try {
        await _firestore.runTransaction((transaction) async {
          final senderWalletSnap = await transaction.get(senderWalletRef);
          if (!senderWalletSnap.exists) {
            throw Exception('Sender wallet not found');
          }

          final latestBalance =
              (senderWalletSnap.data()?['balance'] as num?)?.toDouble() ?? 0.0;
          if (latestBalance < amount) {
            throw Exception('Insufficient balance at commit time');
          }

          transaction.update(senderWalletRef, {
            'balance': latestBalance - amount,
            'updatedAt': Timestamp.fromDate(DateTime.now()),
          });

          transaction.set(txRef, txPayload);

          if (!isInstant) {
            final paymentRequestRef =
                _firestore.collection('payment_requests').doc(txId);
            transaction.set(paymentRequestRef, {
              'senderId': sender.uid,
              'receiverId': receiver.uid,
              'senderName': sender.displayName,
              'amount': amount,
              'status': 'pending',
              'createdAt': Timestamp.fromDate(now),
              'transactionId': txId,
              'note': note,
              'riskScore': finalRiskScore,
              'riskLevel': finalRiskLevel == RiskLevel.high
                  ? 'HIGH'
                  : finalRiskLevel == RiskLevel.medium
                      ? 'MEDIUM'
                      : 'LOW',
            });
          }
        });

        debugPrint(
          '[TransactionService] Firestore write success. txId=$txId, senderBalanceBefore=$senderBalanceBefore, senderBalanceAfter=${senderBalanceBefore - amount}',
        );
      } catch (createError, createStack) {
        debugPrint('[TransactionService] Firestore write failed: $createError');
        debugPrint('[TransactionService] Error stack trace: $createStack');
        return {
          'success': false,
          'error': 'Failed to create transaction. Amount not deducted.',
          'details': createError.toString(),
        };
      }

      try {
        await _createBackendTransactionRequest(
          transactionId: txId,
          sender: sender,
          receiver: receiver,
          amount: amount,
          note: note,
          delayMinutes: normalizedDelayMinutes,
        );
      } catch (backendSyncError, backendSyncStack) {
        debugPrint(
            '[TransactionService] Backend sync failed (non-fatal). txId=$txId, error=$backendSyncError');
        debugPrint(
            '[TransactionService] Backend sync stack: $backendSyncStack');
      }

      if (isInstant) {
        final receiverCredited = await _walletService.addBalance(
          userId: receiver.uid,
          amount: amount,
        );
        if (!receiverCredited) {
          debugPrint(
              '[TransactionService] Receiver credit failed for txId=$txId receiverId=${receiver.uid}');
          return {
            'success': false,
            'error':
                'Transaction created but receiver credit failed. Please contact support.',
            'transactionId': txId,
          };
        }

        await _notificationService.sendPaymentCompletedNotification(
          receiverId: receiver.uid,
          senderName: sender.displayName,
          amount: amount,
          transactionId: txId,
        );
      } else {
        final receiverDoc =
            await _firestore.collection('users').doc(receiver.uid).get();
        final receiverFcmToken =
            (receiverDoc.data()?['fcmToken'] as String?) ?? '';
        debugPrint(
            '[TransactionService] Receiver FCM token present? ${receiverFcmToken.isNotEmpty}');

        try {
          await _notificationService.sendPaymentRequestNotification(
            receiverId: receiver.uid,
            receiverFcmToken: receiverFcmToken,
            senderName: sender.displayName,
            senderId: sender.uid,
            amount: amount,
            transactionId: txId,
            risk: risk,
          );
          debugPrint(
              '[TransactionService] Notification trigger success for txId=$txId');
        } catch (notifError, notifStack) {
          debugPrint(
              '[TransactionService] Notification error (non-fatal): $notifError');
          debugPrint('[TransactionService] Notification stack: $notifStack');
        }
      }

      await _logTransactionToBackend(
        transactionId: txId,
        senderId: sender.uid,
        receiverId: receiver.uid,
        amount: amount,
        status: isInstant ? 'completed' : 'pending',
        riskLevel: finalRiskLabel,
        riskScore: finalRiskScore,
        note: note,
      );

      _invalidateUserCaches(sender.uid);
      _invalidateUserCaches(receiver.uid);

      return {
        'success': true,
        'transactionId': txId,
        'isInstant': isInstant,
        'delayMinutes': normalizedDelayMinutes,
        'riskLevel': risk.levelLabel,
        'riskScore': risk.score,
        'delayRecommended': delayRecommended,
      };
    } catch (e, st) {
      debugPrint('[TransactionService] Error initiating payment: $e');
      debugPrint('[TransactionService] Error stack trace: $st');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Approve a pending payment (receiver approves)
  Future<Map<String, dynamic>> approvePayment(
    String transactionId, {
    bool addToTrustedContacts = false,
  }) async {
    try {
      final txRef = _firestore.collection('transactions').doc(transactionId);
      final txDoc = await txRef.get();

      if (!txDoc.exists) {
        return {'success': false, 'error': 'Transaction not found'};
      }

      final tx = TransactionModel.fromFirestore(txDoc);

      if (tx.status != TransactionStatus.pending) {
        return {'success': false, 'error': 'Transaction is not pending'};
      }

      if (tx.isExpired) {
        await _processTimeout(transactionId, tx);
        return {'success': false, 'error': 'Transaction has expired'};
      }

      if (tx.releaseAt != null && DateTime.now().isBefore(tx.releaseAt!)) {
        return {
          'success': false,
          'error':
              'This payment is delayed until ${tx.releaseAt!.toLocal().toString().split('.').first}',
        };
      }

      // New accounts can occasionally miss wallet bootstrap.
      // Receiver creates their own wallet during approve to unblock settlement.
      await _walletService.createWallet(
        userId: tx.receiverId,
        initialBalance: 0,
      );

      final approveResult = await _invokePaymentCallable(
        'approveEscrowPayment',
        {'transactionId': transactionId},
      );
      if (approveResult['ok'] != true) {
        return {
          'success': false,
          'error': (approveResult['error'] ?? 'Unable to approve payment')
              .toString(),
        };
      }

      await _approveBackendTransaction(
        transactionId: transactionId,
        receiverId: tx.receiverId,
        addToTrustedContacts: addToTrustedContacts,
      );

      // Notify sender to enter PIN
      await _notificationService.sendApprovalNotification(
        senderId: tx.senderId,
        receiverName: tx.receiverName,
        amount: tx.amount,
        transactionId: transactionId,
      );

      _invalidateUserCaches(tx.senderId);
      _invalidateUserCaches(tx.receiverId);

      return {'success': true, 'requiresPin': true};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Complete payment after PIN verification
  Future<Map<String, dynamic>> completePayment(String transactionId) async {
    try {
      final txRef = _firestore.collection('transactions').doc(transactionId);
      final txDoc = await txRef.get();

      if (!txDoc.exists) {
        return {'success': false, 'error': 'Transaction not found'};
      }

      final tx = TransactionModel.fromFirestore(txDoc);

      if (tx.status != TransactionStatus.approved) {
        return {'success': false, 'error': 'Transaction not approved'};
      }

      final completion = await _invokePaymentCallable(
        'completeEscrowPayment',
        {'transactionId': transactionId},
      );
      if (completion['ok'] != true) {
        return {
          'success': false,
          'error':
              (completion['error'] ?? 'Unable to complete payment').toString(),
        };
      }

      await _logTransactionToBackend(
        transactionId: transactionId,
        senderId: tx.senderId,
        receiverId: tx.receiverId,
        amount: tx.amount,
        status: 'completed',
        riskLevel: tx.riskLevel ?? 'Low Risk',
        riskScore: ((tx.riskScore ?? 0) / 100),
        note: tx.note,
      );

      // Notify receiver
      await _notificationService.sendPaymentCompletedNotification(
        receiverId: tx.receiverId,
        senderName: tx.senderName,
        amount: tx.amount,
        transactionId: transactionId,
      );

      return {'success': true};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Reject a pending payment
  Future<bool> rejectPayment(String transactionId) async {
    try {
      final txRef = _firestore.collection('transactions').doc(transactionId);
      final txDoc = await txRef.get();

      if (!txDoc.exists) return false;

      final tx = TransactionModel.fromFirestore(txDoc);

      if (tx.status != TransactionStatus.pending) return false;

      final rejected = await _invokePaymentCallable(
        'rejectEscrowPayment',
        {
          'transactionId': transactionId,
          'reason': 'Rejected by receiver',
        },
      );
      if (rejected['ok'] != true) {
        return false;
      }

      await _rejectBackendTransaction(
        transactionId: transactionId,
        receiverId: tx.receiverId,
      );

      await _logTransactionToBackend(
        transactionId: transactionId,
        senderId: tx.senderId,
        receiverId: tx.receiverId,
        amount: tx.amount,
        status: 'rejected',
        riskLevel: tx.riskLevel ?? 'Low Risk',
        riskScore: ((tx.riskScore ?? 0) / 100),
        note: tx.note,
      );

      // Notify sender
      await _notificationService.sendRejectionNotification(
        senderId: tx.senderId,
        receiverName: tx.receiverName,
        amount: tx.amount,
        transactionId: transactionId,
      );

      _invalidateUserCaches(tx.senderId);
      _invalidateUserCaches(tx.receiverId);

      return true;
    } catch (e) {
      debugPrint('Error rejecting payment: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> emergencyCancelPayment(
    String transactionId,
  ) async {
    try {
      final txRef = _firestore.collection('transactions').doc(transactionId);
      final txDoc = await txRef.get();
      if (!txDoc.exists) {
        return {'success': false, 'error': 'Transaction not found'};
      }

      final tx = TransactionModel.fromFirestore(txDoc);
      final now = DateTime.now();
      final canCancelStatus = tx.status == TransactionStatus.pending ||
          tx.status == TransactionStatus.approved;
      if (!canCancelStatus) {
        return {
          'success': false,
          'error': 'This transaction can no longer be cancelled.',
        };
      }
      if (tx.cancelUntil != null && now.isAfter(tx.cancelUntil!)) {
        return {
          'success': false,
          'error': 'Emergency cancel window expired.',
        };
      }

      final cancelled = await _invokePaymentCallable(
        'cancelEscrowPayment',
        {
          'transactionId': transactionId,
          'reason': 'Emergency sender cancel',
        },
      );
      if (cancelled['ok'] != true) {
        return {
          'success': false,
          'error':
              (cancelled['error'] ?? 'Unable to cancel payment').toString(),
        };
      }

      await _api.post(
        '/payments/transactions/$transactionId/emergency-cancel',
        {
          'senderId': tx.senderId,
          'reason': 'Emergency sender cancel',
        },
        timeout: const Duration(seconds: 5),
        retries: 1,
      );

      await _logTransactionToBackend(
        transactionId: transactionId,
        senderId: tx.senderId,
        receiverId: tx.receiverId,
        amount: tx.amount,
        status: 'refunded',
        riskLevel: tx.riskLevel ?? 'Medium Risk',
        riskScore: ((tx.riskScore ?? 0) / 100),
        note: tx.note,
      );

      _invalidateUserCaches(tx.senderId);
      _invalidateUserCaches(tx.receiverId);

      return {'success': true};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<void> _processTimeout(
      String transactionId, TransactionModel tx) async {
    await _invokePaymentCallable(
      'timeoutEscrowPayment',
      {'transactionId': transactionId},
    );
  }

  Future<Map<String, dynamic>> _invokePaymentCallable(
    String callableName,
    Map<String, dynamic> payload,
  ) async {
    try {
      final callable = _functions.httpsCallable(callableName);
      final result = await callable.call(payload);
      final map = Map<String, dynamic>.from(
        (result.data as Map?) ?? const <String, dynamic>{},
      );
      return map;
    } on FirebaseFunctionsException catch (e) {
      return {
        'ok': false,
        'error': e.message ?? e.code,
      };
    } catch (e) {
      return {
        'ok': false,
        'error': e.toString(),
      };
    }
  }

  Stream<List<TransactionModel>> watchUserTransactions(String userId) {
    return _firestore
        .collection('transactions')
        .where(Filter.or(
          Filter('senderId', isEqualTo: userId),
          Filter('receiverId', isEqualTo: userId),
        ))
        .orderBy('createdAt', descending: true)
        .limit(25)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => TransactionModel.fromFirestore(doc))
            .toList());
  }

  Future<PaginatedTransactions> getTransactionsPage({
    required String userId,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 20,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('transactions')
        .where(Filter.or(
          Filter('senderId', isEqualTo: userId),
          Filter('receiverId', isEqualTo: userId),
        ))
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await query.get();
    final docs = snapshot.docs;
    return PaginatedTransactions(
      items: docs.map((d) => TransactionModel.fromFirestore(d)).toList(),
      lastDoc: docs.isNotEmpty ? docs.last : null,
      hasMore: docs.length == limit,
    );
  }

  Stream<List<TransactionModel>> watchPendingRequestsForReceiver(
      String userId) {
    return _firestore
        .collection('transactions')
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => TransactionModel.fromFirestore(doc))
            .toList());
  }

  Stream<TransactionModel?> watchTransaction(String transactionId) {
    return _firestore
        .collection('transactions')
        .doc(transactionId)
        .snapshots()
        .map((doc) => doc.exists ? TransactionModel.fromFirestore(doc) : null);
  }

  Future<List<TransactionModel>> getRecentTransactions(String userId) async {
    try {
      if (_isRecentCacheValid(userId)) {
        return List<TransactionModel>.from(_recentTxCache[userId] ?? const []);
      }

      final snapshot = await _firestore
          .collection('transactions')
          .where(Filter.or(
            Filter('senderId', isEqualTo: userId),
            Filter('receiverId', isEqualTo: userId),
          ))
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();
      final items = snapshot.docs
          .map((doc) => TransactionModel.fromFirestore(doc))
          .toList();
      _cacheRecent(userId, items);
      return items;
    } catch (e) {
      return [];
    }
  }

  Map<String, dynamic> evaluateRuleBasedRiskPreview({
    required bool isTrustedContact,
    required bool hasPastTransactionsWithReceiver,
    required double amount,
  }) {
    var score = 18;
    final warnings = <String>[];

    if (!hasPastTransactionsWithReceiver) {
      score += 24;
      warnings.add('First transaction with this receiver');
    }

    if (amount >= 5000) {
      score += 34;
      warnings.add('Large amount transaction');
    } else if (amount >= 2000) {
      score += 16;
      warnings.add('Higher-than-usual amount');
    }

    if (!isTrustedContact) {
      score += 22;
      warnings.add('Receiver is not in trusted contacts');
    }

    score = score.clamp(0, 100);
    final riskLevel = score >= 75
        ? 'High Risk'
        : score >= 40
            ? 'Medium Risk'
            : 'Safe';

    return {
      'score': score,
      'riskLevel': riskLevel,
      'warnings': warnings,
    };
  }

  /// Returns recent people this user has SENT money to (for suggestions)
  Future<List<TransactionModel>> getRecentSentPartners(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('transactions')
          .where('senderId', isEqualTo: userId)
          .where('status', isEqualTo: 'completed')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();
      // De-duplicate by receiverUpiId, keep most recent
      final seen = <String>{};
      final results = <TransactionModel>[];
      for (final doc in snapshot.docs) {
        final tx = TransactionModel.fromFirestore(doc);
        if (!seen.contains(tx.receiverUpiId)) {
          seen.add(tx.receiverUpiId);
          results.add(tx);
        }
      }
      return results;
    } catch (e) {
      return [];
    }
  }

  Future<List<double>> _getSenderHistoricalAmounts(String senderId) async {
    try {
      final snapshot = await _firestore
          .collection('transactions')
          .where('senderId', isEqualTo: senderId)
          .where('status', isEqualTo: 'completed')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      return snapshot.docs
          .map((d) => (d.data()['amount'] as num?)?.toDouble() ?? 0)
          .where((v) => v > 0)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<int> _countSenderTransactionsLast24h(String senderId) async {
    try {
      final since = DateTime.now().subtract(const Duration(hours: 24));
      final aggregate = await _firestore
          .collection('transactions')
          .where('senderId', isEqualTo: senderId)
          .where('createdAt', isGreaterThan: Timestamp.fromDate(since))
          .count()
          .get();
      return aggregate.count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<List<TransactionModel>> getUserTransactionsForCurrentMonth(
      String userId) async {
    try {
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final nextMonthStart = DateTime(now.year, now.month + 1, 1);

      final snapshot = await _firestore
          .collection('transactions')
          .where(Filter.or(
            Filter('senderId', isEqualTo: userId),
            Filter('receiverId', isEqualTo: userId),
          ))
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('createdAt', isLessThan: Timestamp.fromDate(nextMonthStart))
          .orderBy('createdAt', descending: true)
          .limit(200)
          .get();

      return snapshot.docs
          .map((doc) => TransactionModel.fromFirestore(doc))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>?> _verifyPaymentWithBackend({
    required String senderId,
    required String receiverId,
    required double amount,
    required bool isTrustedContact,
    required int txCountLast24h,
    required bool unusualSpendingPattern,
    required List<double> historicalAmounts,
  }) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) return null;

    return _api.post(
      '/payments/verify',
      {
        'senderId': senderId,
        'receiverId': receiverId,
        'amount': amount,
        'known_receiver': isTrustedContact,
        'tx_count_last_24h': txCountLast24h,
        'device_mismatch': false,
        'location_mismatch': false,
        'unusual_spending_pattern': unusualSpendingPattern,
        'historical_amounts': historicalAmounts,
      },
      bearerToken: token,
      timeout: const Duration(seconds: 5),
    );
  }

  Future<void> _logTransactionToBackend({
    required String transactionId,
    required String senderId,
    required String receiverId,
    required double amount,
    required String status,
    required String riskLevel,
    required double riskScore,
    String? note,
  }) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) return;

    await _api.post(
      '/payments/transactions/log',
      {
        'transactionId': transactionId,
        'senderId': senderId,
        'receiverId': receiverId,
        'amount': amount,
        'status': status,
        'riskLevel': riskLevel,
        'riskScore': riskScore,
        'note': note,
      },
      bearerToken: token,
      timeout: const Duration(seconds: 5),
      retries: 1,
    );
  }

  Future<void> _createBackendTransactionRequest({
    required String transactionId,
    required UserModel sender,
    required UserModel receiver,
    required double amount,
    String? note,
    int delayMinutes = 0,
  }) async {
    await _api.post(
      '/payments/transactions/request',
      {
        'clientTransactionId': transactionId,
        'senderId': sender.uid,
        'receiverId': receiver.uid,
        'senderName': sender.displayName,
        'receiverName': receiver.displayName,
        'senderUpiId': sender.upiId,
        'receiverUpiId': receiver.upiId,
        'amount': amount,
        'note': note,
        'delayMinutes': delayMinutes,
      },
      timeout: const Duration(seconds: 5),
      retries: 1,
    );
  }

  Future<void> _approveBackendTransaction({
    required String transactionId,
    required String receiverId,
    required bool addToTrustedContacts,
  }) async {
    await _api.post(
      '/payments/transactions/$transactionId/approve',
      {
        'receiverId': receiverId,
        'addToTrustedContacts': addToTrustedContacts,
      },
      timeout: const Duration(seconds: 5),
      retries: 1,
    );
  }

  Future<void> _rejectBackendTransaction({
    required String transactionId,
    required String receiverId,
  }) async {
    await _api.post(
      '/payments/transactions/$transactionId/reject',
      {
        'receiverId': receiverId,
      },
      timeout: const Duration(seconds: 5),
      retries: 1,
    );
  }

  Future<List<Map<String, dynamic>>> fetchBackendTransactionHistory(
    String userId,
  ) async {
    final response = await _api.get(
      '/payments/transactions/history/$userId',
      cacheable: true,
      cacheTtl: const Duration(seconds: 20),
    );
    if (response == null) return const [];

    final raw = response['data'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> fetchSecurityDashboard(String userId) async {
    final response = await _api.get(
      '/payments/dashboard/$userId',
      cacheable: true,
      cacheTtl: const Duration(seconds: 25),
    );

    if (response == null) {
      return _buildSecurityDashboardFromFirestore(userId);
    }

    final rawData = response['data'];
    if (rawData is Map) {
      return Map<String, dynamic>.from(rawData);
    }

    // Backward compatibility: some environments may return the payload directly.
    if (response['totalTransactions'] != null ||
        response['safeTransactions'] != null ||
        response['highRiskTransactions'] != null) {
      return response;
    }

    return _buildSecurityDashboardFromFirestore(userId);
  }

  Future<List<Map<String, dynamic>>> fetchAuditLogs(
    String userId, {
    int limit = 40,
  }) async {
    final response = await _api.get(
      '/payments/transactions/logs/$userId?limit=$limit',
      cacheable: true,
      cacheTtl: const Duration(seconds: 15),
    );
    if (response == null) {
      return _buildAuditLogsFromFirestore(userId, limit: limit);
    }

    final raw = response['data'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return _buildAuditLogsFromFirestore(userId, limit: limit);
  }

  Future<Map<String, dynamic>> _buildSecurityDashboardFromFirestore(
    String userId,
  ) async {
    final since = DateTime.now().subtract(const Duration(days: 30));
    final query = await _firestore
        .collection('transactions')
        .where(Filter.or(
          Filter('senderId', isEqualTo: userId),
          Filter('receiverId', isEqualTo: userId),
        ))
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .limit(300)
        .get();

    var safe = 0;
    var medium = 0;
    var high = 0;
    var highRiskVolume = 0.0;

    for (final doc in query.docs) {
      final data = doc.data();
      final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
      final score = (data['riskScore'] as num?)?.toDouble() ?? 0.0;
      final normalizedScore = score > 1 ? score : score * 100;

      if (normalizedScore >= 75) {
        high += 1;
        highRiskVolume += amount;
      } else if (normalizedScore >= 40) {
        medium += 1;
      } else {
        safe += 1;
      }
    }

    return {
      'windowDays': 30,
      'totalTransactions': query.docs.length,
      'safeTransactions': safe,
      'mediumRiskTransactions': medium,
      'highRiskTransactions': high,
      'preventedFraudCount': high,
      'highRiskVolume': highRiskVolume,
    };
  }

  Future<List<Map<String, dynamic>>> _buildAuditLogsFromFirestore(
    String userId, {
    int limit = 40,
  }) async {
    final logs = <Map<String, dynamic>>[];

    final txSnap = await _firestore
        .collection('transactions')
        .where(Filter.or(
          Filter('senderId', isEqualTo: userId),
          Filter('receiverId', isEqualTo: userId),
        ))
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    var index = 0;
    for (final doc in txSnap.docs) {
      final data = doc.data();
      index += 1;
      logs.add({
        'blockIndex': index,
        'eventType': 'TRANSACTION_${(data['status'] ?? 'UNKNOWN').toString().toUpperCase()}',
        'status': data['status'] ?? 'unknown',
        'amount': (data['amount'] as num?)?.toDouble() ?? 0.0,
        'hash': doc.id,
        'previousHash': index > 1 ? txSnap.docs[index - 2].id : 'GENESIS',
        'createdAt': (data['createdAt'] as Timestamp?)?.toDate().toIso8601String(),
      });
    }

    return logs;
  }
}
