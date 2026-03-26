import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/trusted_contact_model.dart';
import '../models/user_model.dart';

class ContactsService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, List<TrustedContact>> _trustedCacheByOwner = {};
  final Map<String, DateTime> _trustedCacheUpdatedAt = {};
  final Map<String, Future<void>> _inFlightLoads = {};
  static const Duration _cacheTtl = Duration(minutes: 2);

  List<TrustedContact> _trustedContacts = [];
  List<TrustedContact> get trustedContacts => _trustedContacts;

  bool _isCacheValid(String userId) {
    final updatedAt = _trustedCacheUpdatedAt[userId];
    if (updatedAt == null) return false;
    return DateTime.now().difference(updatedAt) < _cacheTtl;
  }

  void _writeCache(String userId, List<TrustedContact> contacts) {
    _trustedCacheByOwner[userId] = List<TrustedContact>.from(contacts);
    _trustedCacheUpdatedAt[userId] = DateTime.now();
  }

  List<TrustedContact> _readCache(String userId) {
    return List<TrustedContact>.from(_trustedCacheByOwner[userId] ?? const []);
  }

  Future<void> loadTrustedContacts(String userId) async {
    if (_isCacheValid(userId)) {
      _trustedContacts = _readCache(userId);
      notifyListeners();
      return;
    }

    if (_inFlightLoads.containsKey(userId)) {
      await _inFlightLoads[userId];
      _trustedContacts = _readCache(userId);
      notifyListeners();
      return;
    }

    final load = () async {
    try {
      final snapshot = await _firestore
          .collection('trusted_contacts')
          .where('ownerUserId', isEqualTo: userId)
          .get();

      final contacts = snapshot.docs
          .map((doc) => TrustedContact.fromFirestore(doc))
          .toList();

      _writeCache(userId, contacts);
      _trustedContacts = contacts;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading trusted contacts: $e');
    }
    }();

    _inFlightLoads[userId] = load;
    await load;
    _inFlightLoads.remove(userId);
  }

  Stream<List<TrustedContact>> watchTrustedContacts(String userId) {
    return _firestore
        .collection('trusted_contacts')
        .where('ownerUserId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          final contacts = snapshot.docs
              .map((doc) => TrustedContact.fromFirestore(doc))
              .toList();
          _writeCache(userId, contacts);
          _trustedContacts = contacts;
          return contacts;
        });
  }

  Future<String?> addTrustedContact({
    required String ownerUserId,
    required UserModel contact,
  }) async {
    try {
      // Check if already trusted
      final existing = await _firestore
          .collection('trusted_contacts')
          .where('ownerUserId', isEqualTo: ownerUserId)
          .where('contactUserId', isEqualTo: contact.uid)
          .get();

      if (existing.docs.isNotEmpty) {
        return 'Contact already trusted';
      }

      await _firestore.collection('trusted_contacts').add({
        'ownerUserId': ownerUserId,
        'contactUserId': contact.uid,
        'contactName': contact.displayName,
        'contactUpiId': contact.upiId,
        'contactPhone': contact.phone,
        'addedAt': Timestamp.fromDate(DateTime.now()),
      });

      final newContact = TrustedContact(
        id: '${ownerUserId}_${contact.uid}',
        ownerUserId: ownerUserId,
        contactUserId: contact.uid,
        contactName: contact.displayName,
        contactUpiId: contact.upiId,
        contactPhone: contact.phone,
        addedAt: DateTime.now(),
      );
      final cached = _readCache(ownerUserId);
      cached.insert(0, newContact);
      _writeCache(ownerUserId, cached);
      _trustedContacts = cached;
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<bool> removeTrustedContact(String contactId, String ownerUserId) async {
    try {
      await _firestore.collection('trusted_contacts').doc(contactId).delete();

      final updated = _readCache(ownerUserId)
          .where((c) => c.id != contactId)
          .toList();
      _writeCache(ownerUserId, updated);
      _trustedContacts = updated;
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> isTrustedContact({
    required String ownerUserId,
    required String contactUserId,
  }) async {
    if (_isCacheValid(ownerUserId)) {
      return _readCache(ownerUserId)
          .any((c) => c.contactUserId == contactUserId);
    }

    final query = await _firestore
        .collection('trusted_contacts')
        .where('ownerUserId', isEqualTo: ownerUserId)
        .where('contactUserId', isEqualTo: contactUserId)
        .limit(1)
        .get();
    return query.docs.isNotEmpty;
  }

  Future<MerchantSettings?> getMerchantSettings(String merchantId) async {
    try {
      final doc = await _firestore
          .collection('merchant_settings')
          .doc(merchantId)
          .get();
      if (doc.exists) return MerchantSettings.fromFirestore(doc);
      // Return default settings
      return MerchantSettings(merchantId: merchantId, fastMode: true);
    } catch (e) {
      return null;
    }
  }

  Future<void> updateMerchantSettings(MerchantSettings settings) async {
    await _firestore
        .collection('merchant_settings')
        .doc(settings.merchantId)
        .set(settings.toMap());
  }
}
