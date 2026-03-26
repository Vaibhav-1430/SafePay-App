import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:async';
import '../models/user_model.dart';
import '../utils/app_error_handler.dart';
import 'app_lock_service.dart';
import 'notification_service.dart';

class _PendingSignupData {
  final String name;
  final String email;
  final String phone;
  final UserType userType;
  final String? businessName;
  final MerchantType? merchantType;

  const _PendingSignupData({
    required this.name,
    required this.email,
    required this.phone,
    required this.userType,
    this.businessName,
    this.merchantType,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'userType': userType.name,
      'businessName': businessName,
      'merchantType': merchantType?.name,
    };
  }

  static _PendingSignupData? fromMap(Map<String, dynamic> data) {
    final name = (data['name'] ?? '').toString().trim();
    final email = (data['email'] ?? '').toString().trim();
    final phone = (data['phone'] ?? '').toString().trim();
    final userTypeRaw = (data['userType'] ?? '').toString().trim();
    if (name.isEmpty || phone.isEmpty || userTypeRaw.isEmpty) {
      return null;
    }

    final userType = userTypeRaw == UserType.merchant.name
        ? UserType.merchant
        : UserType.personal;
    final merchantTypeRaw = (data['merchantType'] ?? '').toString().trim();
    final parsedMerchantType = merchantTypeRaw.isEmpty
        ? null
        : MerchantType.values.firstWhere(
            (e) => e.name == merchantTypeRaw,
            orElse: () => MerchantType.other,
          );

    return _PendingSignupData(
      name: name,
      email: email,
      phone: phone,
      userType: userType,
      businessName: (data['businessName'] ?? '').toString().trim().isEmpty
          ? null
          : (data['businessName'] as String).trim(),
      merchantType: userType == UserType.merchant ? parsedMerchantType : null,
    );
  }
}

class ProfileUpdateResult {
  final bool success;
  final bool deferred;
  final String message;

  const ProfileUpdateResult({
    required this.success,
    required this.deferred,
    required this.message,
  });
}

class DeleteAccountResult {
  final bool success;
  final bool requiresRecentLogin;
  final String message;

  const DeleteAccountResult({
    required this.success,
    required this.requiresRecentLogin,
    required this.message,
  });
}

class PinSetupResult {
  final bool success;
  final String message;

  const PinSetupResult({
    required this.success,
    required this.message,
  });
}

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-south1');
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final AppLockService _appLockService = const AppLockService();
  final Connectivity _connectivity = Connectivity();

  User? _firebaseUser;
  UserModel? _currentUser;
  bool _isLoading = false;
  bool _isAppUnlocked = false;
  String? _verificationId;
  String? _deleteAccountVerificationId;
  int? _resendToken;
  String? _lastOtpPhone;
  _PendingSignupData? _pendingSignupData;
  DateTime? _otpCooldownUntil;
  DateTime? _otpBlockedUntil;
  int _otpVerifyFailureCount = 0;
  bool _isOtpSendInFlight = false;
  bool _isOtpVerifyInFlight = false;
  bool _isProfileUpdating = false;
  bool _isDeleteAccountInFlight = false;
  bool _isSessionReady = false;
  Future<void>? _bootstrapInFlight;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _userProfileSubscription;
  StreamSubscription<dynamic>? _connectivitySubscription;

  static const int _maxOtpVerifyFailures = 5;
  static const String _pendingSignupDataStorageKey = 'pending_signup_data';

  User? get firebaseUser => _firebaseUser;
  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _firebaseUser != null && _currentUser != null;
  bool get isProfileUpdating => _isProfileUpdating;
  bool get isDeleteAccountInFlight => _isDeleteAccountInFlight;
  bool get isSessionReady => _isSessionReady;
  bool get hasUpiPinSet => _currentUser?.hasUpiPin ?? false;
  bool get isAppPinSet => _currentUser?.appPinSet == true;
  bool get isAppUnlocked => _isAppUnlocked;
  String? get pendingOtpPhone => _lastOtpPhone;
  int get otpCooldownSecondsRemaining {
    final until = _otpCooldownUntil;
    if (until == null) return 0;
    final secs = until.difference(DateTime.now()).inSeconds;
    return secs > 0 ? secs : 0;
  }

  int get otpBlockedSecondsRemaining {
    final until = _otpBlockedUntil;
    if (until == null) return 0;
    final secs = until.difference(DateTime.now()).inSeconds;
    return secs > 0 ? secs : 0;
  }

  AuthService() {
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((result) {
      if (_firebaseUser == null || !_hasNetwork(result)) return;
      unawaited(_syncPendingProfileUpdate(_firebaseUser!.uid));
    });

    _auth.authStateChanges().listen((user) async {
      _isSessionReady = false;
      _firebaseUser = user;
      notifyListeners();
      try {
        if (user != null) {
          await _hydrateUserSession(user.uid);
          await NotificationService().saveFcmToken(user.uid);
          _isAppUnlocked = false;
        } else {
          await _userProfileSubscription?.cancel();
          _userProfileSubscription = null;
          _currentUser = null;
          _isAppUnlocked = false;
        }
      } finally {
        _isSessionReady = true;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _userProfileSubscription?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _hydrateUserSession(String uid) async {
    await _loadCachedUserProfile(uid);
    _attachUserProfileListener(uid);
    await _loadUserProfile(uid);
    await _syncPendingProfileUpdate(uid);
  }

  Future<void> _loadUserProfile(String uid) async {
    try {
      final doc = await _retryWithBackoff(
        () => _firestore.collection('users').doc(uid).get(),
      );
      if (doc.exists) {
        _currentUser = UserModel.fromFirestore(doc);
        await _ensureCriticalProfileFields(uid);
        await _cacheUserProfile(_currentUser!);
      } else {
        final fbUser = _firebaseUser;
        if (fbUser != null && fbUser.uid == uid) {
          final signupData = _pendingSignupData ?? await _readPersistedPendingSignupData();
          final fallback = _buildFallbackProfile(
            fbUser,
            signupData: signupData,
          );
          await createUserIfNotExists(profile: fallback);
          final recovered = await _retryWithBackoff(
            () => _firestore.collection('users').doc(uid).get(),
          );
          if (recovered.exists) {
            _currentUser = UserModel.fromFirestore(recovered);
            await _ensureCriticalProfileFields(uid);
            await _cacheUserProfile(_currentUser!);
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
    }
  }

  UserModel _buildFallbackProfile(
    User user, {
    _PendingSignupData? signupData,
  }) {
    final effectiveSignupData = signupData ?? _pendingSignupData;
    final safePhone = _normalizePhone(
      effectiveSignupData?.phone ??
          _lastOtpPhone ??
          user.phoneNumber ??
          '',
    );
    final now = DateTime.now();
    return UserModel(
      uid: user.uid,
      name: _sanitizeName(
        effectiveSignupData?.name.isNotEmpty == true
            ? effectiveSignupData!.name
            : (user.displayName ?? ''),
      ),
      email: effectiveSignupData?.email ?? (user.email ?? ''),
      phone: safePhone,
      userType: effectiveSignupData?.userType ?? UserType.personal,
      upiId: _buildSafeUpiId(safePhone, user.uid),
      createdAt: now,
      businessName: effectiveSignupData?.businessName,
      merchantType: effectiveSignupData?.merchantType,
    );
  }

  bool _isUidDerivedUpiId(String upiId, String uid) {
    final current = upiId.trim().toLowerCase();
    if (current.isEmpty) return false;
    final uidBased = _buildSafeUpiId('', uid);
    return current == uidBased;
  }

  void _attachUserProfileListener(String uid) {
    _userProfileSubscription?.cancel();
    _userProfileSubscription = _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) async {
      if (!doc.exists) return;
      final nextUser = UserModel.fromFirestore(doc);
      _currentUser = nextUser;
      await _cacheUserProfile(nextUser);
      notifyListeners();
    }, onError: (error) {
      debugPrint('User profile subscription error: $error');
    });
  }

  static final RegExp _upiIdRegex =
      RegExp(r'^[a-z0-9][a-z0-9._-]{1,30}@[a-z]{2,}$');

  bool _isValidUpiId(String? upiId) {
    final value = (upiId ?? '').trim().toLowerCase();
    return _upiIdRegex.hasMatch(value);
  }

  String _sanitizeName(String raw) {
    final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return 'SafePay User';
    return collapsed.length > 60 ? collapsed.substring(0, 60) : collapsed;
  }

  String _sanitizeNameForRules(String raw) {
    final candidate = _sanitizeName(raw);
    if (candidate.length < 3) return 'SafePay User';
    return candidate;
  }

  String _buildSafeUpiId(String phone, String uid) {
    final digits = _normalizePhone(phone);
    final local = digits.isNotEmpty
        ? digits
        : uid.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase().substring(0, 10);
    return '${local.toLowerCase()}@safepay';
  }

  Future<void> _ensureCriticalProfileFields(String uid) async {
    final user = _currentUser;
    if (user == null) return;

    final patch = <String, dynamic>{};

    final safeName = _sanitizeName(user.name);
    if (safeName != user.name) {
      patch['name'] = safeName;
    }

    final normalizedPhone = _normalizePhone(user.phone);
    if (normalizedPhone.isNotEmpty && normalizedPhone != user.phone) {
      patch['phone'] = normalizedPhone;
    }

    if (!_isValidUpiId(user.upiId)) {
      patch['upiId'] = _buildSafeUpiId(normalizedPhone.isNotEmpty ? normalizedPhone : user.phone, uid);
    }

    if (patch.isEmpty) return;

    try {
      await _retryWithBackoff(
        () => _firestore.collection('users').doc(uid).set(
          patch,
          SetOptions(merge: true),
        ),
      );

      _currentUser = user.copyWith(
        name: (patch['name'] as String?) ?? user.name,
        phone: (patch['phone'] as String?) ?? user.phone,
        upiId: (patch['upiId'] as String?) ?? user.upiId,
      );
      await _cacheUserProfile(_currentUser!);
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to self-heal profile fields for $uid: $e');
    }
  }

  String _profileCacheKey(String uid) => 'user_profile_cache_$uid';
  String _pendingProfileUpdateKey(String uid) => 'pending_profile_update_$uid';

  Future<void> _cacheUserProfile(UserModel user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _profileCacheKey(user.uid),
        jsonEncode(user.toCacheMap()),
      );
    } catch (e) {
      debugPrint('Failed to cache profile: $e');
    }
  }

  Future<void> _loadCachedUserProfile(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_profileCacheKey(uid));
      if (cached == null || cached.isEmpty) return;

      final map = jsonDecode(cached) as Map<String, dynamic>;
      _currentUser = UserModel.fromMap(map, uid: uid);
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load cached profile: $e');
    }
  }

  Future<T> _retryWithBackoff<T>(
    Future<T> Function() operation, {
    int maxAttempts = 3,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await operation();
      } catch (error) {
        lastError = error;
        if (!AppErrorHandler.isRetryableNetworkError(error) ||
            attempt == maxAttempts) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }

    throw lastError ?? Exception('Retry failed');
  }

  bool _hasNetwork(dynamic result) {
    if (result is List<ConnectivityResult>) {
      return result.any((item) => item != ConnectivityResult.none);
    }
    if (result is ConnectivityResult) {
      return result != ConnectivityResult.none;
    }
    return true;
  }

  Future<void> _enqueuePendingProfileUpdate(
    String uid,
    Map<String, dynamic> patch,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _pendingProfileUpdateKey(uid);
    final existingRaw = prefs.getString(key);
    final merged = <String, dynamic>{};

    if (existingRaw != null && existingRaw.isNotEmpty) {
      merged.addAll(jsonDecode(existingRaw) as Map<String, dynamic>);
    }

    merged.addAll(patch);
    merged['queuedAt'] = DateTime.now().toIso8601String();
    await prefs.setString(key, jsonEncode(merged));
  }

  Future<Map<String, dynamic>?> _readPendingProfileUpdate(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingProfileUpdateKey(uid));
    if (raw == null || raw.isEmpty) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> _clearPendingProfileUpdate(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingProfileUpdateKey(uid));
  }

  Future<void> _syncPendingProfileUpdate(String uid) async {
    final pending = await _readPendingProfileUpdate(uid);
    if (pending == null || pending.isEmpty) return;

    final patch = Map<String, dynamic>.from(pending)
      ..remove('queuedAt');
    if (patch.isEmpty) {
      await _clearPendingProfileUpdate(uid);
      return;
    }

    try {
      await _retryWithBackoff(
        () => _firestore.collection('users').doc(uid).set(patch, SetOptions(merge: true)),
      );
      await _clearPendingProfileUpdate(uid);
    } catch (e) {
      debugPrint('Pending profile sync failed: $e');
    }
  }

  Future<ProfileUpdateResult> updateDisplayName(String newName) async {
    final user = _currentUser;
    if (user == null) {
      return const ProfileUpdateResult(
        success: false,
        deferred: false,
        message: 'Please sign in and try again.',
      );
    }

    final normalized = newName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      return const ProfileUpdateResult(
        success: false,
        deferred: false,
        message: 'Name cannot be empty.',
      );
    }
    if (normalized.length < 3) {
      return const ProfileUpdateResult(
        success: false,
        deferred: false,
        message: 'Name must be at least 3 characters.',
      );
    }

    _isProfileUpdating = true;
    _currentUser = user.copyWith(name: normalized);
    notifyListeners();
    await _cacheUserProfile(_currentUser!);

    final patch = <String, dynamic>{'name': normalized};
    try {
      await _retryWithBackoff(
        () => _firestore.collection('users').doc(user.uid).set(patch, SetOptions(merge: true)),
      );
      return const ProfileUpdateResult(
        success: true,
        deferred: false,
        message: 'Name updated successfully.',
      );
    } catch (error) {
      if (AppErrorHandler.isRetryableNetworkError(error)) {
        await _enqueuePendingProfileUpdate(user.uid, patch);
        return const ProfileUpdateResult(
          success: true,
          deferred: true,
          message: 'You are offline. Name saved locally and will sync automatically.',
        );
      }

      _currentUser = user;
      await _cacheUserProfile(user);
      return ProfileUpdateResult(
        success: false,
        deferred: false,
        message: AppErrorHandler.toUserMessage(error),
      );
    } finally {
      _isProfileUpdating = false;
      notifyListeners();
    }
  }

  Future<ProfileUpdateResult> updateProfilePhoto({
    required Uint8List bytes,
    String fileExtension = 'jpg',
  }) async {
    final user = _currentUser;
    if (user == null) {
      return const ProfileUpdateResult(
        success: false,
        deferred: false,
        message: 'Please sign in and try again.',
      );
    }

    _isProfileUpdating = true;
    notifyListeners();

    try {
      final ext = fileExtension.toLowerCase().replaceAll('.', '');
      final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';
      final ref = _storage
          .ref()
          .child('users/${user.uid}/profile/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext');

      await _retryWithBackoff(
        () => ref.putData(
          bytes,
          SettableMetadata(contentType: contentType),
        ),
      );

      final url = await ref.getDownloadURL();
      await _retryWithBackoff(
        () => _firestore.collection('users').doc(user.uid).set(
          {'profileImageUrl': url},
          SetOptions(merge: true),
        ),
      );

      _currentUser = user.copyWith(profileImageUrl: url);
      await _cacheUserProfile(_currentUser!);
      return const ProfileUpdateResult(
        success: true,
        deferred: false,
        message: 'Profile photo updated.',
      );
    } catch (error) {
      return ProfileUpdateResult(
        success: false,
        deferred: false,
        message: AppErrorHandler.toUserMessage(
          error,
          fallback: 'Failed to upload profile photo. Please retry.',
        ),
      );
    } finally {
      _isProfileUpdating = false;
      notifyListeners();
    }
  }

  Future<String?> startSignupOtp({
    required String name,
    required String email,
    required String phone,
    required UserType userType,
    String? businessName,
    MerchantType? merchantType,
  }) async {
    final normalized = _normalizePhone(phone);
    if (normalized.isEmpty) {
      return 'Enter a valid phone number';
    }

    try {
      final availabilityError = await _validatePhoneAvailableForSignup(normalized);
      if (availabilityError != null) {
        return availabilityError;
      }

      _pendingSignupData = _PendingSignupData(
        name: name.trim(),
        email: email.trim(),
        phone: normalized,
        userType: userType,
        businessName: businessName,
        merchantType: merchantType,
      );
      await _persistPendingSignupData(_pendingSignupData!);

      return sendOTP(_toE164(normalized));
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> _validatePhoneAvailableForSignup(String normalizedPhone) async {
    final e164 = _toE164(normalizedPhone);

    try {
      final callable = _functions.httpsCallable('checkPhoneAvailability');
      final result = await callable.call({
        'phone': e164,
      });
      final data = Map<String, dynamic>.from(
        (result.data as Map?) ?? const <String, dynamic>{},
      );
      final isAvailable = data['available'] == true;
      if (!isAvailable) {
        return 'Phone number already exists. Please login instead.';
      }
      return null;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'already-exists') {
        return 'Phone number already exists. Please login instead.';
      }
      if (e.code == 'failed-precondition') {
        // App Check can lag during fresh debug installs.
        // Fall back to direct Firestore check instead of blocking signup.
        debugPrint('[Signup] App Check not ready for checkPhoneAvailability. Falling back to client-side phone lookup.');
      }
      if (e.code == 'not-found' || e.code == 'unimplemented') {
        // Backward-compatible fallback for environments where the function
        // is not deployed yet.
      } else if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        // Use fallback lookup on transient backend/network issues.
        debugPrint('[Signup] checkPhoneAvailability unavailable. Falling back to client-side phone lookup.');
      } else if (kDebugMode) {
        debugPrint('[Signup] checkPhoneAvailability failed [${e.code}] ${e.message ?? 'No details'}. Falling back to client-side phone lookup.');
      }
    } catch (_) {
      // Fallback below.
    }

    final existing = await getUserByPhone(normalizedPhone);
    if (existing != null) {
      return 'Phone number already exists. Please login instead.';
    }
    return null;
  }

  Future<String?> startLoginOtp({required String phone}) async {
    final normalized = _normalizePhone(phone);
    if (normalized.isEmpty) {
      return 'Enter a valid phone number';
    }

    try {
      // Login must not pre-block on phone lookup; resolve/create user after OTP by UID.
      _pendingSignupData = null;
      await _clearPersistedPendingSignupData();
      return sendOTP(_toE164(normalized));
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> _persistPendingSignupData(_PendingSignupData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingSignupDataStorageKey, jsonEncode(data.toMap()));
  }

  Future<_PendingSignupData?> _readPersistedPendingSignupData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingSignupDataStorageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return _PendingSignupData.fromMap(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearPersistedPendingSignupData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingSignupDataStorageKey);
  }

  Future<void> _bootstrapUserAfterPhoneAuth(String e164Phone) async {
    if (_bootstrapInFlight != null) {
      await _bootstrapInFlight;
      return;
    }

    final completer = Completer<void>();
    _bootstrapInFlight = completer.future;
    try {
      await _bootstrapUserAfterPhoneAuthImpl(e164Phone);
      completer.complete();
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _bootstrapInFlight = null;
    }
  }

  Future<void> _bootstrapUserAfterPhoneAuthImpl(String e164Phone) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Phone authentication failed');
    }

    final digits = _normalizePhone(e164Phone);
    if (digits.isEmpty) {
      throw Exception('Invalid phone number in authenticated session.');
    }

    await _claimPhoneOwnershipForCurrentUser(digits);

    final existsByUid = await checkUserExists(user.uid);
    final deviceId = await _getOrCreateDeviceInstallId();
    final signupData = _pendingSignupData ?? await _readPersistedPendingSignupData();

    final sameDeviceUsers = await _firestore
        .collection('users')
        .where('deviceBinding.activeDeviceId', isEqualTo: deviceId)
        .limit(4)
        .get();

    final knownCurrent = sameDeviceUsers.docs.any((d) => d.id == user.uid);
    if (!existsByUid && !knownCurrent && sameDeviceUsers.docs.length >= 3) {
      throw Exception('Device limit reached. Contact support to add another account.');
    }

    if (existsByUid) {
      await _upgradeExistingProfileFromBootstrapData(
        uid: user.uid,
        e164Phone: e164Phone,
        signupData: signupData,
      );
      await _bindCurrentDevice(user.uid);
      await _loadUserProfile(user.uid);
      await _ensureCriticalProfileFields(user.uid);
      _pendingSignupData = null;
      await _clearPersistedPendingSignupData();
      return;
    }

    final profile = UserModel(
      uid: user.uid,
      name: _sanitizeName(
        signupData?.name.isNotEmpty == true
            ? signupData!.name
            : (user.displayName ?? 'SafePay User'),
      ),
      email: signupData?.email ?? (user.email ?? ''),
      phone: digits,
      userType: signupData?.userType ?? UserType.personal,
      upiId: _buildSafeUpiId(digits, user.uid),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      businessName: signupData?.businessName,
      merchantType: signupData?.merchantType,
      appPinSet: false,
    );

    await createUserIfNotExists(profile: profile);

    await _bindCurrentDevice(user.uid);

    _pendingSignupData = null;
    await _clearPersistedPendingSignupData();
    await _loadUserProfile(user.uid);
  }

  Future<void> _claimPhoneOwnershipForCurrentUser(String normalizedPhone) async {
    final callable = _functions.httpsCallable('claimPhoneNumberOwnership');
    try {
      await callable.call({'phone': _toE164(normalizedPhone)});
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'already-exists') {
        throw Exception('Phone number already exists. Please login instead.');
      }
      if (e.code == 'failed-precondition') {
        // App Check issue in debug/early startup; use transactional fallback.
        await _claimPhoneOwnershipClientSide(normalizedPhone);
        return;
      }
      if (e.code == 'not-found' || e.code == 'unimplemented') {
        await _claimPhoneOwnershipClientSide(normalizedPhone);
        return;
      }
      rethrow;
    }
  }

  Future<void> _claimPhoneOwnershipClientSide(String normalizedPhone) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw Exception('Invalid user session. Please sign in again.');
    }

    final indexRef = _firestore.collection('user_phone_index').doc(normalizedPhone);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(indexRef);
      if (snap.exists) {
        final ownerUid = (snap.data()?['uid'] ?? '').toString();
        if (ownerUid.isNotEmpty && ownerUid != uid) {
          throw Exception('Phone number already exists. Please login instead.');
        }
      }

      final now = Timestamp.fromDate(DateTime.now());
      tx.set(indexRef, {
        'uid': uid,
        'phoneNumber': normalizedPhone,
        'updatedAt': now,
        'createdAt': snap.exists ? (snap.data()?['createdAt'] ?? now) : now,
      }, SetOptions(merge: true));
    });
  }

  Future<void> _upgradeExistingProfileFromBootstrapData({
    required String uid,
    required String e164Phone,
    required _PendingSignupData? signupData,
  }) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return;

    final existing = UserModel.fromFirestore(doc);
    final safePhone = _normalizePhone(
      signupData?.phone ?? e164Phone,
    );
    final patch = <String, dynamic>{};

    if (safePhone.isNotEmpty && existing.phone != safePhone) {
      patch['phone'] = safePhone;
      patch['phoneNumber'] = safePhone;
      patch['phoneNormalized'] = safePhone;
    }

    if (signupData != null) {
      final safeSignupName = _sanitizeName(signupData.name);
      if ((existing.name.trim().isEmpty || existing.name == 'SafePay User') &&
          safeSignupName != existing.name) {
        patch['name'] = safeSignupName;
      }

      if (existing.email.trim().isEmpty && signupData.email.trim().isNotEmpty) {
        patch['email'] = signupData.email.trim();
      }

      if (existing.userType != signupData.userType) {
        patch['userType'] = signupData.userType.name;
      }

      if (signupData.userType == UserType.merchant) {
        if ((existing.businessName ?? '').trim().isEmpty &&
            (signupData.businessName ?? '').trim().isNotEmpty) {
          patch['businessName'] = signupData.businessName!.trim();
        }
        if (existing.merchantType == null && signupData.merchantType != null) {
          patch['merchantType'] = signupData.merchantType!.name;
        }
      }
    }

    if (safePhone.isNotEmpty &&
        (_isUidDerivedUpiId(existing.upiId, uid) || !_isValidUpiId(existing.upiId))) {
      patch['upiId'] = _buildSafeUpiId(safePhone, uid);
    }

    if (patch.isEmpty) return;

    patch['updatedAt'] = Timestamp.fromDate(DateTime.now());

    await _firestore.collection('users').doc(uid).set(
      patch,
      SetOptions(merge: true),
    );
  }

  Future<bool> checkUserExists(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.exists;
  }

  Future<void> createUserIfNotExists({
    required UserModel profile,
  }) async {
    final userRef = _firestore.collection('users').doc(profile.uid);
    final walletRef = _firestore.collection('wallets').doc(profile.uid);
    final phoneIndexRef = _firestore.collection('user_phone_index').doc(profile.phone);
    final initialBalance = profile.userType == UserType.personal ? 5000.0 : 10000.0;

    await _firestore.runTransaction((tx) async {
      final indexDoc = await tx.get(phoneIndexRef);
      if (indexDoc.exists) {
        final ownerUid = (indexDoc.data()?['uid'] ?? '').toString();
        if (ownerUid.isNotEmpty && ownerUid != profile.uid) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'already-exists',
            message: 'Phone number already exists. Please login instead.',
          );
        }
      }

      final existingUser = await tx.get(userRef);
      if (!existingUser.exists) {
        final payload = Map<String, dynamic>.from(profile.toMap())
          ..['phoneNumber'] = profile.phone
          ..['phoneNormalized'] = profile.phone
          ..['appPinSet'] = profile.appPinSet
          ..['updatedAt'] = Timestamp.fromDate(DateTime.now());
        tx.set(userRef, payload);
      }

      tx.set(phoneIndexRef, {
        'uid': profile.uid,
        'phoneNumber': profile.phone,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
        'createdAt': indexDoc.exists
            ? (indexDoc.data()?['createdAt'] ?? Timestamp.fromDate(DateTime.now()))
            : Timestamp.fromDate(DateTime.now()),
      }, SetOptions(merge: true));

      final existingWallet = await tx.get(walletRef);
      if (!existingWallet.exists) {
        final now = Timestamp.fromDate(DateTime.now());
        tx.set(walletRef, {
          'userId': profile.uid,
          'balance': initialBalance,
          'createdAt': now,
          'updatedAt': now,
        });
      }
    });
  }

  // Phone OTP flow
  Future<String?> sendOTP(String phoneNumber, {bool isResend = false}) async {
    if (_isOtpSendInFlight) {
      return 'OTP request already in progress. Please wait...';
    }

    _isOtpSendInFlight = true;
    _isLoading = true;
    notifyListeners();

    try {
      final gateError = await _checkOtpRateLimit(phoneNumber);
      if (gateError != null) {
        return gateError;
      }

      String? lastError;
      var recaptchaFallbackEnabled = false;
      for (int attempt = 1; attempt <= 2; attempt++) {
        try {
          debugPrint(
            '[OTP] verifyPhoneNumber start phone=$phoneNumber isResend=$isResend attempt=$attempt hasResendToken=${_resendToken != null}',
          );
          _lastOtpPhone = phoneNumber;
          final completer = Completer<String?>();

          await _auth.verifyPhoneNumber(
            phoneNumber: phoneNumber,
            forceResendingToken: isResend ? _resendToken : null,
            timeout: const Duration(seconds: 60),
            verificationCompleted: (PhoneAuthCredential credential) async {
              debugPrint('[OTP] verificationCompleted received from Firebase.');
              try {
                await _auth.signInWithCredential(credential);
                _otpVerifyFailureCount = 0;
                final otpPhone = _lastOtpPhone ?? _auth.currentUser?.phoneNumber;
                if (otpPhone != null) {
                  await _resetOtpRateLimit(otpPhone);
                  await _bootstrapUserAfterPhoneAuth(otpPhone);
                } else if (_auth.currentUser != null) {
                  await _loadUserProfile(_auth.currentUser!.uid);
                }
                _isAppUnlocked = false;
                notifyListeners();
                if (!completer.isCompleted) {
                  completer.complete(null);
                }
              } catch (e) {
                debugPrint('[OTP] Auto verification sign-in failed: $e');
                if (!completer.isCompleted) {
                  final text = e.toString();
                  if (text.toLowerCase().contains('phone number already exists')) {
                    completer.complete('Phone number already exists. Please login instead.');
                  } else {
                    completer.complete('Auto verification failed. Please try OTP manually.');
                  }
                }
              }
            },
            verificationFailed: (FirebaseAuthException e) {
              debugPrint(
                '[OTP] verificationFailed code=${e.code} message=${e.message}',
              );
              if (!completer.isCompleted) {
                completer.complete(_mapPhoneAuthError(e));
              }
            },
            codeSent: (String verificationId, int? resendToken) {
              debugPrint(
                '[OTP] codeSent verificationIdLength=${verificationId.length} resendToken=${resendToken ?? 'null'}',
              );
              _verificationId = verificationId;
              _resendToken = resendToken;
              notifyListeners();
              if (!completer.isCompleted) {
                completer.complete(null);
              }
            },
            codeAutoRetrievalTimeout: (String verificationId) {
              debugPrint('[OTP] codeAutoRetrievalTimeout fired.');
              _verificationId = verificationId;
              notifyListeners();
            },
          );

          final result = await completer.future.timeout(
            const Duration(seconds: 70),
            onTimeout: () => 'Timed out while sending OTP. Please try again.',
          );

          if (result == null) {
            return null;
          }

          if (!recaptchaFallbackEnabled && _looksLikeAppNotAuthorized(result)) {
            recaptchaFallbackEnabled = true;
            if (defaultTargetPlatform == TargetPlatform.android) {
              debugPrint('[OTP] Enabling Android forceRecaptchaFlow fallback after app authorization failure.');
              await _auth.setSettings(forceRecaptchaFlow: true);
              continue;
            }
          }

          return result;
        } catch (e) {
          debugPrint('[OTP] verifyPhoneNumber threw (attempt $attempt): $e');
          final msg = e.toString();
          if (msg.toUpperCase().contains('BILLING_NOT_ENABLED')) {
            lastError = _billingNotEnabledMessage;
            break;
          }
          if (!recaptchaFallbackEnabled && _looksLikeAppNotAuthorized(msg)) {
            recaptchaFallbackEnabled = true;
            if (defaultTargetPlatform == TargetPlatform.android) {
              debugPrint('[OTP] verifyPhoneNumber threw app authorization error; retrying with forceRecaptchaFlow.');
              await _auth.setSettings(forceRecaptchaFlow: true);
              continue;
            }
          }
          lastError = msg;
          if (!_isRetryableOtpError(msg) || attempt == 2) {
            break;
          }
          await Future<void>.delayed(Duration(milliseconds: 700 * attempt));
        }
      }

      return lastError ?? 'Unable to send OTP. Please try again.';
    } finally {
      _isOtpSendInFlight = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  bool _isRetryableOtpError(String message) {
    final text = message.toLowerCase();
    return text.contains('network') ||
        text.contains('timeout') ||
        text.contains('unavailable') ||
        text.contains('internal');
  }

  bool _looksLikeAppNotAuthorized(String message) {
    final text = message.toLowerCase();
    return text.contains('app-not-authorized') ||
        text.contains('not authorized for firebase phone auth') ||
        text.contains('play_integrity_token') ||
        text.contains('invalid app info');
  }

  Future<String?> resendLastOtp() async {
    if (_lastOtpPhone == null || _lastOtpPhone!.isEmpty) {
      return 'No phone number found for OTP resend';
    }
    return sendOTP(_lastOtpPhone!, isResend: true);
  }

  Future<String?> verifyOTP(String otp) async {
    if (_verificationId == null) return 'No verification ID found';
    if (_isOtpVerifyInFlight) {
      return 'OTP verification already in progress. Please wait...';
    }
    if (_otpVerifyFailureCount >= _maxOtpVerifyFailures) {
      return 'Too many invalid OTP attempts. Please request a new OTP after a short wait.';
    }

    _isOtpVerifyInFlight = true;
    _isLoading = true;
    notifyListeners();

    try {
      debugPrint('[OTP] verifyOTP start for entered code length=${otp.length}.');
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );
      await _auth.signInWithCredential(credential);
      _otpVerifyFailureCount = 0;

      final otpPhone = _lastOtpPhone ?? _auth.currentUser?.phoneNumber;
      if (otpPhone != null) {
        await _resetOtpRateLimit(otpPhone);
        await _bootstrapUserAfterPhoneAuth(otpPhone);
      } else if (_auth.currentUser != null) {
        await _loadUserProfile(_auth.currentUser!.uid);
      }

      _isAppUnlocked = false;
      notifyListeners();
      debugPrint('[OTP] verifyOTP success.');
      return null;
    } on FirebaseAuthException catch (e) {
      debugPrint('[OTP] verifyOTP failed code=${e.code} message=${e.message}');
      if (e.code == 'invalid-verification-code' || e.code == 'session-expired') {
        _otpVerifyFailureCount += 1;
      }
      return _mapPhoneAuthError(e);
    } catch (e) {
      final msg = e.toString();
      if (msg.toLowerCase().contains('phone number already exists')) {
        return 'Phone number already exists. Please login instead.';
      }
      if (msg.toUpperCase().contains('BILLING_NOT_ENABLED')) {
        return _billingNotEnabledMessage;
      }
      return msg;
    } finally {
      _isOtpVerifyInFlight = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> _checkOtpRateLimit(String e164Phone) async {
    final appCheckError = await _ensureAppCheckReady();
    if (appCheckError != null) {
      return appCheckError;
    }

    try {
      final callable = _functions.httpsCallable('otpRequestGuard');
      final deviceId = await _getOrCreateDeviceInstallId();
      final result = await callable.call({
        'phone': e164Phone,
        'deviceId': deviceId,
        // Keep off by default; backend supports exponential backoff toggling.
        'useExponentialBackoff': false,
      });

      final data = Map<String, dynamic>.from(
        (result.data as Map?) ?? const <String, dynamic>{},
      );
      final allowed = data['allowed'] == true;
      if (allowed) {
        _otpCooldownUntil = null;
        _otpBlockedUntil = null;
        notifyListeners();
        return null;
      }

      final errorCode = (data['errorCode'] ?? '').toString();
      final waitSeconds = (data['waitSeconds'] as num?)?.toInt() ?? 0;

      if (errorCode == 'WAIT_30_SEC') {
        _otpCooldownUntil = DateTime.now().add(Duration(seconds: waitSeconds));
        notifyListeners();
        return 'WAIT_30_SEC';
      }

      if (errorCode == 'BLOCKED_24_HOURS') {
        _otpBlockedUntil = DateTime.now().add(Duration(seconds: waitSeconds));
        notifyListeners();
        return 'BLOCKED_24_HOURS';
      }

      return 'Unable to send OTP at the moment. Please try again.';
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found' || e.code == 'unimplemented') {
        return 'OTP security service is not deployed. Deploy Cloud Functions and try again.';
      }
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        return 'OTP security service is temporarily unavailable. Please retry in a few seconds.';
      }
      if (e.code == 'unauthenticated') {
        if (kDebugMode) {
          return 'App Check debug token is not accepted yet. Open Firebase Console > App Check > Android app > Manage debug tokens, add this device token, then retry.';
        }
        return 'App integrity check failed. Please update SafePay from the official source and try again.';
      }
      if (e.code == 'permission-denied') {
        debugPrint('[OTP] otpRequestGuard returned permission-denied. Continuing OTP flow with client-side fallback.');
        _otpCooldownUntil = null;
        _otpBlockedUntil = null;
        notifyListeners();
        return null;
      }
      if (e.code == 'invalid-argument') {
        return 'Invalid OTP request format. Please re-enter your phone number and try again.';
      }
      if (e.code == 'internal') {
        return 'OTP security service hit an internal error. Please retry in a few seconds.';
      }
      if (e.code == 'failed-precondition') {
        if (kDebugMode) {
          return 'App Check debug token is missing or not allowlisted. Open Firebase Console > App Check > Android app > Manage debug tokens, add this device token, then retry.';
        }
        return 'Security check failed. Please update the app and try again.';
      }
      debugPrint('[OTP] Cloud Function rate-limit check failed: ${e.code} ${e.message}');
      if (kDebugMode) {
        return 'Unable to validate OTP request. [${e.code}] ${e.message ?? 'No details'}';
      }
      return 'Unable to validate OTP request. Please try again.';
    } catch (e) {
      debugPrint('[OTP] Unexpected rate-limit check error: $e');
      if (kDebugMode) {
        return 'Unable to validate OTP request. $e';
      }
      return 'Unable to validate OTP request. Please try again.';
    }
  }

  Future<String?> _ensureAppCheckReady() async {
    final connectivity = await _connectivity.checkConnectivity();
    if (!_hasNetwork(connectivity)) {
      return 'No internet connection. Please reconnect and try again.';
    }

    // Token creation can lag on fresh installs. Retry with a slightly longer
    // backoff to reduce false negatives on first launch and app reinstalls.
    const retryDelaysMs = [300, 500, 800, 1200, 1800, 2600];
    for (int attempt = 1; attempt <= retryDelaysMs.length; attempt++) {
      try {
        final forceRefresh = attempt >= retryDelaysMs.length;
        final token = await FirebaseAppCheck.instance.getToken(forceRefresh);
        if (token != null && token.isNotEmpty) {
          return null;
        }
      } catch (e) {
        debugPrint('[AppCheck] Token fetch attempt $attempt failed: $e');
      }

      if (attempt < retryDelaysMs.length) {
        await Future<void>.delayed(
          Duration(milliseconds: retryDelaysMs[attempt - 1]),
        );
      }
    }

    // Do not block user flows here. Callable Functions still enforce App Check
    // and return the precise server-side failure reason if verification fails.
    debugPrint('[AppCheck] Token still unavailable after retries; continuing and deferring strict validation to backend enforcement.');
    return null;
  }

  Future<void> _resetOtpRateLimit(String e164Phone) async {
    try {
      final callable = _functions.httpsCallable('otpResetLimiter');
      await callable.call({'phone': e164Phone});
      _otpCooldownUntil = null;
      _otpBlockedUntil = null;
      notifyListeners();
    } catch (e) {
      debugPrint('[OTP] Failed to reset server-side OTP limiter: $e');
    }
  }

  String formatOtpError(String error) {
    if (error == 'WAIT_30_SEC') {
      final remaining = otpCooldownSecondsRemaining;
      return remaining > 0
          ? 'Please wait $remaining seconds before requesting another OTP.'
          : 'Please wait a few seconds before requesting another OTP.';
    }

    if (error == 'BLOCKED_24_HOURS') {
      final remaining = otpBlockedSecondsRemaining;
      final hours = remaining ~/ 3600;
      final mins = (remaining % 3600) ~/ 60;
      return hours > 0
          ? 'Too many OTP attempts. Try again in ${hours}h ${mins}m.'
          : 'Too many OTP attempts. Try again later.';
    }

    return error;
  }

  bool shouldOfferOtpRetry(String error) {
    final text = error.toLowerCase();
    return text.contains('network') ||
        text.contains('retry') ||
        text.contains('unavailable') ||
        text.contains('integrity') ||
        text.contains('app check') ||
        text.contains('play integrity') ||
        text.contains('timed out');
  }

  String upiIdForDisplay(UserModel user) {
    if (_isValidUpiId(user.upiId)) {
      return user.upiId;
    }

    final generated = _buildSafeUpiId(user.phone, user.uid);
    unawaited(_retryWithBackoff(
      () => _firestore.collection('users').doc(user.uid).set(
        {'upiId': generated},
        SetOptions(merge: true),
      ),
    ));
    return generated;
  }

  Future<String> _getOrCreateDeviceInstallId() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'safepay_device_install_id';
    final existing = prefs.getString(key);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final entropy = '${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().millisecondsSinceEpoch}';
    final digest = sha256.convert(utf8.encode(entropy)).toString();
    final value = 'sp_${digest.substring(0, 24)}';
    await prefs.setString(key, value);
    return value;
  }

  Future<void> _bindCurrentDevice(String uid) async {
    final installId = await _getOrCreateDeviceInstallId();
    await _firestore.collection('users').doc(uid).set({
      'deviceBinding': {
        'activeDeviceId': installId,
        'platform': defaultTargetPlatform.name,
        'lastSeenAt': Timestamp.fromDate(DateTime.now()),
      },
    }, SetOptions(merge: true));
  }

  String _mapPhoneAuthError(FirebaseAuthException e) {
    final code = e.code.toLowerCase();
    final message = (e.message ?? '').toUpperCase();

    if (code == 'app-not-authorized' ||
        message.contains('PLAY_INTEGRITY_TOKEN') ||
        message.contains('INVALID APP INFO')) {
      return _appNotAuthorizedMessage;
    }

    if (code == 'billing-not-enabled' || message.contains('BILLING_NOT_ENABLED')) {
      return _billingNotEnabledMessage;
    }

    if (code == 'invalid-phone-number') {
      return 'Invalid phone number. Please enter a valid number with country code.';
    }

    if (code == 'too-many-requests') {
      return 'Too many OTP attempts. Please wait a few minutes and try again.';
    }

    if (code == 'network-request-failed') {
      return 'Network error while sending OTP. Check your connection and retry.';
    }

    return e.message ?? 'Unable to send OTP. Check phone number and try again.';
  }

  static const String _billingNotEnabledMessage =
      'Phone OTP is not enabled for this Firebase project yet. Enable billing (Blaze) in Firebase/GCP, then retry.';

  static const String _appNotAuthorizedMessage =
      'This build is not authorized for Firebase Phone Auth. Verify Android package name, add BOTH SHA-1 and SHA-256 for debug/release in Firebase, re-download google-services.json, and enable App Check with Play Integrity.';

  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      await NotificationService().clearFcmToken(uid);
      await _clearLocalSessionState(uid, clearAppPin: false);
    }
    await _auth.signOut();
    await _userProfileSubscription?.cancel();
    _userProfileSubscription = null;
    _currentUser = null;
    _isAppUnlocked = false;
    notifyListeners();
  }

  Future<void> _clearLocalSessionState(
    String uid, {
    bool clearAppPin = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileCacheKey(uid));
    await prefs.remove(_pendingProfileUpdateKey(uid));
    await prefs.remove('upi_pin_hash');
    await _secureStorage.delete(key: _upiPinStorageKey(uid));
    if (clearAppPin) {
      await _appLockService.clearPin(uid);
    }
  }

  Future<DeleteAccountResult> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      return const DeleteAccountResult(
        success: false,
        requiresRecentLogin: false,
        message: 'Invalid user session. Please sign in again.',
      );
    }

    if (_isDeleteAccountInFlight) {
      return const DeleteAccountResult(
        success: false,
        requiresRecentLogin: false,
        message: 'Account deletion already in progress.',
      );
    }

    _isDeleteAccountInFlight = true;
    notifyListeners();

    try {
      // Step 1: Delete all user-owned backend data through trusted server code.
      final callable = _functions.httpsCallable('deleteUserAccountCascade');
      await callable.call({'uid': user.uid});

      // Step 2: Delete Firebase Authentication account.
      await user.delete();

      // Step 3: Purge local state and caches.
      await _clearLocalSessionState(user.uid, clearAppPin: true);
      await _userProfileSubscription?.cancel();
      _userProfileSubscription = null;
      _currentUser = null;
      _firebaseUser = null;
      _isAppUnlocked = false;
      _deleteAccountVerificationId = null;

      return const DeleteAccountResult(
        success: true,
        requiresRecentLogin: false,
        message: 'Account deleted successfully',
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        return const DeleteAccountResult(
          success: false,
          requiresRecentLogin: true,
          message: 'Session expired, please login again',
        );
      }
      if (e.code == 'network-request-failed') {
        return const DeleteAccountResult(
          success: false,
          requiresRecentLogin: false,
          message: 'Network error. Please retry.',
        );
      }
      return DeleteAccountResult(
        success: false,
        requiresRecentLogin: false,
        message: e.message ?? 'Something went wrong, try again',
      );
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unauthenticated') {
        return const DeleteAccountResult(
          success: false,
          requiresRecentLogin: true,
          message: 'Session expired, please login again',
        );
      }
      if (e.code == 'failed-precondition') {
        return const DeleteAccountResult(
          success: false,
          requiresRecentLogin: false,
          message: 'Security check failed. Please retry. If this continues, update SafePay and try again.',
        );
      }
      return DeleteAccountResult(
        success: false,
        requiresRecentLogin: false,
        message: e.message ?? 'Something went wrong, try again',
      );
    } catch (_) {
      return const DeleteAccountResult(
        success: false,
        requiresRecentLogin: false,
        message: 'Something went wrong, try again',
      );
    } finally {
      _isDeleteAccountInFlight = false;
      notifyListeners();
    }
  }

  Future<String?> startDeleteAccountReauthOtp() async {
    final user = _auth.currentUser;
    if (user == null) {
      return 'Invalid user session. Please sign in again.';
    }

    final phone = user.phoneNumber ?? _currentUser?.phone;
    final normalized = _normalizePhone(phone ?? '');
    if (normalized.isEmpty) {
      return 'Phone number unavailable for re-authentication.';
    }

    final appCheckError = await _ensureAppCheckReady();
    if (appCheckError != null) {
      return appCheckError;
    }

    final completer = Completer<String?>();

    await _auth.verifyPhoneNumber(
      phoneNumber: _toE164(normalized),
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          await user.reauthenticateWithCredential(credential);
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        } catch (_) {
          if (!completer.isCompleted) {
            completer.complete('Unable to verify session. Please try again.');
          }
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!completer.isCompleted) {
          completer.complete(_mapPhoneAuthError(e));
        }
      },
      codeSent: (String verificationId, int? resendToken) {
        _deleteAccountVerificationId = verificationId;
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _deleteAccountVerificationId = verificationId;
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 70),
      onTimeout: () => 'Timed out while sending OTP. Please retry.',
    );
  }

  Future<DeleteAccountResult> confirmDeleteAccountWithOtp(String otp) async {
    final user = _auth.currentUser;
    final verificationId = _deleteAccountVerificationId;

    if (user == null) {
      return const DeleteAccountResult(
        success: false,
        requiresRecentLogin: false,
        message: 'Invalid user session. Please sign in again.',
      );
    }

    if (verificationId == null || verificationId.isEmpty) {
      return const DeleteAccountResult(
        success: false,
        requiresRecentLogin: false,
        message: 'Re-authentication OTP not found. Please request OTP again.',
      );
    }

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: otp.trim(),
      );
      await user.reauthenticateWithCredential(credential);
      _deleteAccountVerificationId = null;
      return deleteAccount();
    } on FirebaseAuthException catch (e) {
      return DeleteAccountResult(
        success: false,
        requiresRecentLogin: false,
        message: _mapPhoneAuthError(e),
      );
    } catch (_) {
      return const DeleteAccountResult(
        success: false,
        requiresRecentLogin: false,
        message: 'Unable to verify OTP. Please try again.',
      );
    }
  }

  Future<bool> hasAppLockPin() async {
    final uid = _firebaseUser?.uid;
    if (uid == null) return false;
    final hasLocalPin = await _appLockService.hasAppPin(uid);
    if (hasLocalPin) return true;

    final serverHash = (_currentUser?.appPinHash ?? '').trim();
    if ((_currentUser?.appPinSet ?? false) && serverHash.isNotEmpty) {
      await _appLockService.importHashedAppPin(uid: uid, pinHash: serverHash);
      return true;
    }
    return false;
  }

  Future<void> _ensureProfileAndWalletReadyForAppLock() async {
    final fbUser = _firebaseUser ?? _auth.currentUser;
    if (fbUser == null) {
      throw Exception('Invalid user session. Please sign in again.');
    }

    final persistedSignupData = await _readPersistedPendingSignupData();

    if (_currentUser != null) {
      final fallbackPhone = _normalizePhone(
        _currentUser!.phone.isNotEmpty
            ? _currentUser!.phone
            : (fbUser.phoneNumber ?? _lastOtpPhone ?? ''),
      );
      if (persistedSignupData != null && fallbackPhone.isNotEmpty) {
        await _upgradeExistingProfileFromBootstrapData(
          uid: fbUser.uid,
          e164Phone: _toE164(fallbackPhone),
          signupData: persistedSignupData,
        );
        await _loadUserProfile(fbUser.uid);
      }

      final walletDoc = await _firestore.collection('wallets').doc(fbUser.uid).get();
      if (!walletDoc.exists) {
        await createUserIfNotExists(profile: _currentUser!);
      }
      return;
    }

    final normalizedPhone = _normalizePhone(
      _lastOtpPhone ?? fbUser.phoneNumber ?? '',
    );

    if (normalizedPhone.isNotEmpty) {
      await _bootstrapUserAfterPhoneAuth(_toE164(normalizedPhone));
    } else {
      await _loadUserProfile(fbUser.uid);
    }

    if (_currentUser == null) {
      final fallback = _buildFallbackProfile(fbUser);
      await createUserIfNotExists(profile: fallback);
      _currentUser = fallback;
      await _cacheUserProfile(fallback);
    }

    if (persistedSignupData != null) {
      final fallbackPhone = _normalizePhone(
        _currentUser?.phone ?? fbUser.phoneNumber ?? _lastOtpPhone ?? '',
      );
      if (fallbackPhone.isNotEmpty) {
        await _upgradeExistingProfileFromBootstrapData(
          uid: fbUser.uid,
          e164Phone: _toE164(fallbackPhone),
          signupData: persistedSignupData,
        );
        await _loadUserProfile(fbUser.uid);
      }
    }

    final walletDoc = await _firestore.collection('wallets').doc(fbUser.uid).get();
    if (!walletDoc.exists && _currentUser != null) {
      await createUserIfNotExists(profile: _currentUser!);
    }
  }

  Future<bool> setAppLockPin(String pin) async {
    final uid = _firebaseUser?.uid;
    if (uid == null) return false;
    try {
      await _ensureProfileAndWalletReadyForAppLock();
    } catch (e) {
      debugPrint('[AppLock] Profile bootstrap failed before app PIN save: $e');
      // Continue with local PIN save even when remote bootstrap is flaky.
    }
    final sanitized = pin.trim();
    final ok = await _appLockService.saveAppPin(uid: uid, pin: sanitized);
    if (ok) {
      final appPinHash = _appLockService.hashPin(uid: uid, pin: sanitized);
      final now = DateTime.now();

      var user = _currentUser;
      if (user == null) {
        await _loadUserProfile(uid);
        user = _currentUser;
      }
      if (user == null) {
        final fbUser = _firebaseUser ?? _auth.currentUser;
        if (fbUser != null) {
          final fallback = _buildFallbackProfile(fbUser);
          await createUserIfNotExists(profile: fallback);
          user = fallback;
          _currentUser = fallback;
          await _cacheUserProfile(fallback);
        }
      }
      if (user == null) {
        debugPrint('[AppLock] Unable to resolve user profile for app PIN save.');
        return false;
      }

      final safeName = _sanitizeNameForRules(user.name);
      final safePhone = _normalizePhone(
        user.phone.isNotEmpty
            ? user.phone
            : (_firebaseUser?.phoneNumber ?? _lastOtpPhone ?? ''),
      );
      if (safePhone.isEmpty) {
        debugPrint('[AppLock] Missing phone while saving app PIN.');
        return false;
      }
      final safeUpiId = _isValidUpiId(user.upiId)
          ? user.upiId
          : _buildSafeUpiId(safePhone, uid);

      final patch = <String, dynamic>{
        // Include critical profile fields so strict Firestore rules pass.
        'name': safeName,
        'phone': safePhone,
        'phoneNumber': safePhone,
        'phoneNormalized': safePhone,
        'upiId': safeUpiId,
        'appPinHash': appPinHash,
        'appPinSet': true,
        'appPinCreatedAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      };
      try {
        await _retryWithBackoff(
          () => _firestore.collection('users').doc(uid).set(
            patch,
            SetOptions(merge: true),
          ),
        );
      } catch (error) {
        // Local app lock should not fail due to non-critical remote sync issues.
        await _enqueuePendingProfileUpdate(uid, patch);
        debugPrint('[AppLock] Remote app PIN sync deferred: $error');
      }

      final current = _currentUser;
      if (current != null) {
        _currentUser = current.copyWith(
          name: safeName,
          phone: safePhone,
          upiId: safeUpiId,
          appPinHash: appPinHash,
          appPinSet: true,
          appPinCreatedAt: now,
          updatedAt: now,
        );
        await _cacheUserProfile(_currentUser!);
      }
      _isAppUnlocked = true;
      notifyListeners();
    }
    return ok;
  }

  Future<bool> verifyAppLockPin(String pin) async {
    final uid = _firebaseUser?.uid;
    if (uid == null) return false;
    final sanitized = pin.trim();
    var ok = await _appLockService.verifyAppPin(uid: uid, pin: sanitized);

    if (!ok) {
      final serverHash = (_currentUser?.appPinHash ?? '').trim();
      if (serverHash.isNotEmpty) {
        final attemptedHash = _appLockService.hashPin(uid: uid, pin: sanitized);
        if (attemptedHash == serverHash) {
          await _appLockService.importHashedAppPin(
            uid: uid,
            pinHash: serverHash,
          );
          ok = true;
        }
      }
    }

    if (ok) {
      _isAppUnlocked = true;
      notifyListeners();
    }
    return ok;
  }

  Future<bool> changeAppLockPin({
    required String oldPin,
    required String newPin,
  }) async {
    final uid = _firebaseUser?.uid;
    if (uid == null) return false;
    final ok = await _appLockService.changeAppPin(
      uid: uid,
      oldPin: oldPin,
      newPin: newPin,
    );
    if (ok) {
      notifyListeners();
    }
    return ok;
  }

  void lockApp() {
    _isAppUnlocked = false;
    notifyListeners();
  }

  Future<PinSetupResult> setUpiPin(String pin) async {
    try {
      if (_currentUser == null) {
        return const PinSetupResult(
          success: false,
          message: 'User profile is not ready yet. Please wait and try again.',
        );
      }

      final sanitized = pin.trim();
      if (!RegExp(r'^\d{4}(\d{2})?$').hasMatch(sanitized)) {
        return const PinSetupResult(
          success: false,
          message: 'PIN must be exactly 4 or 6 digits.',
        );
      }

      var user = _currentUser!;
      final safeName = _sanitizeName(user.name);

      // First-run hydration can briefly have an incomplete profile.
      // Recover phone from Firebase Auth and refresh profile before failing.
      var safePhone = _normalizePhone(user.phone);
      if (safePhone.isEmpty) {
        final authPhone = _normalizePhone(_firebaseUser?.phoneNumber ?? '');
        if (authPhone.isNotEmpty) {
          safePhone = authPhone;
        }
      }

      if (safePhone.isEmpty && _firebaseUser != null) {
        await _loadUserProfile(_firebaseUser!.uid);
        user = _currentUser ?? user;
        safePhone = _normalizePhone(user.phone);
      }

      if (safePhone.isEmpty) {
        return const PinSetupResult(
          success: false,
          message: 'Phone number is still syncing. Please wait a moment and try again.',
        );
      }
      final safeUpiId = _isValidUpiId(user.upiId)
          ? user.upiId
          : _buildSafeUpiId(safePhone, user.uid);

      final pinHash = _hashPin(sanitized);
      final now = DateTime.now();

      await _retryWithBackoff(
        () => _firestore.collection('users').doc(user.uid).set({
          // Keep critical fields valid for Firestore rules on update.
          'name': safeName,
          'phone': safePhone,
          'phoneNumber': safePhone,
          'phoneNormalized': safePhone,
          'upiId': safeUpiId,
          'upiPinHash': pinHash,
          'pinHash': pinHash,
          'upiPinCreatedAt': Timestamp.fromDate(now),
          'upiPinLength': sanitized.length,
          'updatedAt': Timestamp.fromDate(now),
        }, SetOptions(merge: true)),
      );

      _currentUser = user.copyWith(
        name: safeName,
        phone: safePhone,
        upiId: safeUpiId,
        upiPinHash: pinHash,
        upiPinCreatedAt: now,
        upiPinLength: sanitized.length,
        updatedAt: now,
      );
      await _cacheUserProfile(_currentUser!);

      // Save hashed PIN in secure storage for local verification fallback.
      await _persistPinHashSecurely(user.uid, pinHash);

      notifyListeners();
      return const PinSetupResult(
        success: true,
        message: 'UPI PIN created successfully.',
      );
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return const PinSetupResult(
          success: false,
          message: 'Permission denied while saving PIN. Please sign in again.',
        );
      }
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        return const PinSetupResult(
          success: false,
          message: 'Network issue while saving PIN. Please retry.',
        );
      }
      return PinSetupResult(
        success: false,
        message: e.message ?? 'Failed to set UPI PIN. Try again.',
      );
    } catch (_) {
      return const PinSetupResult(
        success: false,
        message: 'Failed to set UPI PIN. Try again.',
      );
    }
  }

  Future<bool> verifyUpiPin(String pin) async {
    final sanitized = pin.trim();
    String? expectedHash = _currentUser?.upiPinHash;
    final uid = _currentUser?.uid ?? _firebaseUser?.uid;
    if ((expectedHash == null || expectedHash.isEmpty) && uid != null) {
      expectedHash = await _readPinHashSecurely(uid);
    }
    if (expectedHash == null || expectedHash.isEmpty) {
      return false;
    }

    final pinHash = _hashPin(sanitized);
    return expectedHash == pinHash;
  }

  String _hashPin(String pin) {
    final uidSalt = _currentUser?.uid ?? _firebaseUser?.uid ?? 'safepay';
    final bytes = utf8.encode('$uidSalt::$pin');
    return sha256.convert(bytes).toString();
  }

  String _upiPinStorageKey(String uid) => 'upi_pin_hash_$uid';

  Future<void> _persistPinHashSecurely(String uid, String hash) async {
    await _secureStorage.write(key: _upiPinStorageKey(uid), value: hash);
  }

  Future<String?> _readPinHashSecurely(String uid) async {
    return _secureStorage.read(key: _upiPinStorageKey(uid));
  }

  String _normalizePhone(String phone) {
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('91') && digits.length == 12) {
      digits = digits.substring(2);
    }
    if (digits.length < 10) return '';
    if (digits.length > 10) {
      digits = digits.substring(digits.length - 10);
    }
    return digits;
  }

  String _toE164(String normalizedPhone) {
    return '+91$normalizedPhone';
  }

  Future<void> refreshUser() async {
    if (_firebaseUser != null) {
      await _loadUserProfile(_firebaseUser!.uid);
      await _ensureCriticalProfileFields(_firebaseUser!.uid);
      await _syncPendingProfileUpdate(_firebaseUser!.uid);
      notifyListeners();
    }
  }

  Future<UserModel?> getUserByUpiId(String upiId) async {
    try {
      final query = await _firestore
          .collection('users')
          .where('upiId', isEqualTo: upiId)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        return UserModel.fromFirestore(query.docs.first);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<UserModel?> getUserById(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) return UserModel.fromFirestore(doc);
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Look up a SafePay user by their 10-digit phone number.
  /// The phone stored in Firestore may be in various formats (+91XXXXXXXXXX or XXXXXXXXXX).
  Future<UserModel?> getUserByPhone(String normalizedPhone) async {
    try {
      final normalized = _normalizePhone(normalizedPhone);
      if (normalized.isEmpty) return null;

      // Try exact match first (stored as-is)
      var query = await _firestore
          .collection('users')
          .where('phone', isEqualTo: normalized)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        return UserModel.fromFirestore(query.docs.first);
      }
      // Try with +91 prefix
      query = await _firestore
          .collection('users')
          .where('phoneNormalized', isEqualTo: normalized)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        return UserModel.fromFirestore(query.docs.first);
      }

      query = await _firestore
          .collection('users')
          .where('phoneNumber', isEqualTo: normalized)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        return UserModel.fromFirestore(query.docs.first);
      }

      query = await _firestore
          .collection('users')
          .where('phone', isEqualTo: '+91$normalized')
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        return UserModel.fromFirestore(query.docs.first);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

