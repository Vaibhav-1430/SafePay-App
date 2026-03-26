import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/wallet_model.dart';

class WalletService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  WalletModel? _wallet;

  WalletModel? get wallet => _wallet;
  double get balance => _wallet?.balance ?? 0.0;

  Future<void> createWallet({
    required String userId,
    double initialBalance = 0.0,
  }) async {
    await _firestore.runTransaction((transaction) async {
      final walletRef = _firestore.collection('wallets').doc(userId);
      final snap = await transaction.get(walletRef);
      if (snap.exists) {
        return;
      }

      final now = Timestamp.fromDate(DateTime.now());
      transaction.set(walletRef, {
        'userId': userId,
        'balance': initialBalance,
        'createdAt': now,
        'updatedAt': now,
      });
    });
  }

  Future<WalletModel?> getWallet(String userId) async {
    try {
      final doc = await _firestore.collection('wallets').doc(userId).get();
      if (doc.exists) {
        _wallet = WalletModel.fromFirestore(doc);
        notifyListeners();
        return _wallet;
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching wallet: $e');
      return null;
    }
  }

  Stream<WalletModel?> watchWallet(String userId) {
    return _firestore
        .collection('wallets')
        .doc(userId)
        .snapshots()
        .map((doc) {
      if (doc.exists) {
        _wallet = WalletModel.fromFirestore(doc);
        return _wallet;
      }
      return null;
    });
  }

  Future<bool> addBalance({
    required String userId,
    required double amount,
  }) async {
    try {
      // Use FieldValue.increment — atomic server-side, NO read required.
      // runTransaction() required READ first which was blocked by security rules
      // when sender tried to credit the RECEIVER's wallet (not their own).
      await _firestore.collection('wallets').doc(userId).update({
        'balance': FieldValue.increment(amount),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
      return true;
    } on FirebaseException catch (e) {
      // First top-up can happen before wallet bootstrap finishes.
      // Create the wallet doc and retry once.
      if (e.code == 'not-found') {
        final now = Timestamp.fromDate(DateTime.now());
        await _firestore.collection('wallets').doc(userId).set({
          'userId': userId,
          'balance': amount,
          'createdAt': now,
          'updatedAt': now,
        }, SetOptions(merge: true));
        return true;
      }
      debugPrint('Error adding balance: $e');
      return false;
    } catch (e) {
      debugPrint('Error adding balance: $e');
      return false;
    }
  }

  Future<bool> deductBalance({
    required String userId,
    required double amount,
  }) async {
    try {
      await _firestore.runTransaction((transaction) async {
        final walletRef = _firestore.collection('wallets').doc(userId);
        final walletDoc = await transaction.get(walletRef);

        if (!walletDoc.exists) throw Exception('Wallet not found');

        final currentBalance = (walletDoc.data()!['balance'] as num).toDouble();
        if (currentBalance < amount) {
          throw Exception('Insufficient balance');
        }
        transaction.update(walletRef, {
          'balance': currentBalance - amount,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
      });
      return true;
    } catch (e) {
      debugPrint('Error deducting balance: $e');
      return false;
    }
  }

  Future<String?> topUp({
    required String userId,
    required double amount,
  }) async {
    try {
      final success = await addBalance(userId: userId, amount: amount);
      if (success) {
        // Log a user-owned top-up record so it passes hardened create rules.
        await _firestore.collection('transactions').add({
          'senderId': userId,
          'receiverId': userId,
          'senderName': 'SafePay',
          'receiverName': 'Wallet',
          'senderUpiId': 'wallet@safepay',
          'receiverUpiId': 'wallet@safepay',
          'amount': amount,
          'status': 'completed',
          'type': 'topUp',
          'note': 'Wallet top-up',
          'createdAt': Timestamp.fromDate(DateTime.now()),
          'completedAt': Timestamp.fromDate(DateTime.now()),
          'isEscrow': false,
          'isTrustedContact': false,
        });
        return null;
      }
      return 'Failed to add balance';
    } catch (e) {
      return e.toString();
    }
  }
}
