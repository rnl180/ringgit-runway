import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the sign-in token lives between launches.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// Keychain / Keystore on phones, encrypted local storage on web.
class SecureTokenStore implements TokenStore {
  static const _key = 'auth_token';
  final _storage = const FlutterSecureStorage();

  // Secure storage can be unavailable (e.g. web served over plain http on a
  // LAN address). Then the token lasts only for this session.
  String? _memory;

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key) ?? _memory;
    } catch (_) {
      return _memory;
    }
  }

  @override
  Future<void> write(String token) async {
    _memory = token;
    try {
      await _storage.write(key: _key, value: token);
    } catch (_) {}
  }

  @override
  Future<void> clear() async {
    _memory = null;
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}

class MemoryTokenStore implements TokenStore {
  String? token;
  MemoryTokenStore([this.token]);
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String t) async => token = t;
  @override
  Future<void> clear() async => token = null;
}
