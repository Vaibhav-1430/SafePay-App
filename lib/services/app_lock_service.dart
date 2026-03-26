import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppLockService {
  static const _storage = FlutterSecureStorage();

  const AppLockService();

  String _pinKey(String uid) => 'app_lock_pin_hash_$uid';

  String _hash(String uid, String pin) {
    final bytes = utf8.encode('$uid::$pin');
    return sha256.convert(bytes).toString();
  }

  String hashPin({required String uid, required String pin}) {
    return _hash(uid, pin.trim());
  }

  Future<bool> hasAppPin(String uid) async {
    final value = await _storage.read(key: _pinKey(uid));
    return (value ?? '').isNotEmpty;
  }

  Future<bool> saveAppPin({required String uid, required String pin}) async {
    final sanitized = pin.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(sanitized)) {
      return false;
    }

    await _storage.write(key: _pinKey(uid), value: _hash(uid, sanitized));
    return true;
  }

  Future<void> importHashedAppPin({
    required String uid,
    required String pinHash,
  }) async {
    final normalized = pinHash.trim();
    if (normalized.isEmpty) return;
    await _storage.write(key: _pinKey(uid), value: normalized);
  }

  Future<bool> verifyAppPin({required String uid, required String pin}) async {
    final existing = await _storage.read(key: _pinKey(uid));
    if (existing == null || existing.isEmpty) {
      return false;
    }

    return existing == _hash(uid, pin.trim());
  }

  Future<bool> changeAppPin({
    required String uid,
    required String oldPin,
    required String newPin,
  }) async {
    final isOldCorrect = await verifyAppPin(uid: uid, pin: oldPin);
    if (!isOldCorrect) {
      return false;
    }

    return saveAppPin(uid: uid, pin: newPin);
  }

  Future<void> clearPin(String uid) async {
    await _storage.delete(key: _pinKey(uid));
  }
}
