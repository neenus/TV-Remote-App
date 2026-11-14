import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class KeyStore {
  Future<String?> read(String deviceId);
  Future<void> write(String deviceId, String key);
  Future<void> delete(String deviceId);
}

class MemoryKeyStore implements KeyStore {
  final _map = <String, String>{};
  @override
  Future<String?> read(String deviceId) async => _map[deviceId];
  @override
  Future<void> write(String deviceId, String key) async => _map[deviceId] = key;
  @override
  Future<void> delete(String deviceId) async => _map.remove(deviceId);
}

/// Pairing keys live in the platform secure store (Keychain / Keystore).
class SecureKeyStore implements KeyStore {
  SecureKeyStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  String _k(String id) => 'tv-key-$id';

  @override
  Future<String?> read(String deviceId) => _storage.read(key: _k(deviceId));
  @override
  Future<void> write(String deviceId, String key) =>
      _storage.write(key: _k(deviceId), value: key);
  @override
  Future<void> delete(String deviceId) => _storage.delete(key: _k(deviceId));
}
