import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/app_constants.dart';

class _CacheEntry {
  final DateTime expiresAt;
  final Map<String, dynamic> value;

  const _CacheEntry({required this.expiresAt, required this.value});

  bool get isValid => DateTime.now().isBefore(expiresAt);
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final Map<String, _CacheEntry> _cache = {};

  bool get isEnabled {
    final base = AppConstants.backendApiBaseUrl.trim();
    return base.startsWith('http://') || base.startsWith('https://');
  }

  Uri _uri(String path) {
    final base = AppConstants.backendApiBaseUrl.trim();
    final normalizedBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  String _cacheKey(String method, String path, Map<String, dynamic>? body) {
    return '$method|$path|${body == null ? '' : jsonEncode(body)}';
  }

  Map<String, String> _headers({
    String? bearerToken,
    Map<String, String>? extra,
  }) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (AppConstants.mobileApiKey.isNotEmpty) {
      headers['x-api-key'] = AppConstants.mobileApiKey;
    }
    if (bearerToken != null && bearerToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $bearerToken';
    }
    if (extra != null && extra.isNotEmpty) {
      headers.addAll(extra);
    }

    return headers;
  }

  bool _isRetriableError(Object e) {
    return e is TimeoutException || e is SocketException || e is http.ClientException;
  }

  Future<Map<String, dynamic>?> _executeWithRetry(
    Future<Map<String, dynamic>?> Function() operation, {
    int retries = 2,
  }) async {
    var attempt = 0;
    while (attempt <= retries) {
      try {
        return await operation();
      } catch (e) {
        if (!_isRetriableError(e) || attempt == retries) {
          debugPrint('[ApiService] Request failed: $e');
          return null;
        }
        attempt += 1;
        final backoff = Duration(milliseconds: 250 * attempt * attempt);
        await Future<void>.delayed(backoff);
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> post(
    String path,
    Map<String, dynamic> body, {
    String? bearerToken,
    Duration timeout = const Duration(seconds: 6),
    int retries = 2,
    bool cacheable = false,
    Duration cacheTtl = const Duration(minutes: 2),
    Map<String, String>? headers,
  }) async {
    if (!isEnabled) return null;

    final key = _cacheKey('POST', path, body);
    if (cacheable) {
      final entry = _cache[key];
      if (entry != null && entry.isValid) {
        return entry.value;
      }
    }

    final responseData = await _executeWithRetry(() async {
      final res = await http
          .post(
            _uri(path),
            headers: _headers(bearerToken: bearerToken, extra: headers),
            body: jsonEncode(body),
          )
          .timeout(timeout);

      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('[ApiService] POST $path failed: ${res.statusCode}');
        return null;
      }

      final json = jsonDecode(res.body);
      if (json is! Map<String, dynamic>) return null;
      return (json['data'] is Map<String, dynamic>)
          ? (json['data'] as Map<String, dynamic>)
          : json;
    }, retries: retries);

    if (cacheable && responseData != null) {
      _cache[key] = _CacheEntry(
        expiresAt: DateTime.now().add(cacheTtl),
        value: responseData,
      );
    }

    return responseData;
  }

  Future<Map<String, dynamic>?> get(
    String path, {
    String? bearerToken,
    Duration timeout = const Duration(seconds: 6),
    int retries = 2,
    bool cacheable = true,
    Duration cacheTtl = const Duration(minutes: 2),
    Map<String, String>? headers,
  }) async {
    if (!isEnabled) return null;

    final key = _cacheKey('GET', path, null);
    if (cacheable) {
      final entry = _cache[key];
      if (entry != null && entry.isValid) {
        return entry.value;
      }
    }

    final responseData = await _executeWithRetry(() async {
      final res = await http
          .get(
            _uri(path),
            headers: _headers(bearerToken: bearerToken, extra: headers),
          )
          .timeout(timeout);

      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('[ApiService] GET $path failed: ${res.statusCode}');
        return null;
      }

      final json = jsonDecode(res.body);
      if (json is! Map<String, dynamic>) return null;
      return (json['data'] is Map<String, dynamic>)
          ? (json['data'] as Map<String, dynamic>)
          : json;
    }, retries: retries);

    if (cacheable && responseData != null) {
      _cache[key] = _CacheEntry(
        expiresAt: DateTime.now().add(cacheTtl),
        value: responseData,
      );
    }

    return responseData;
  }
}
