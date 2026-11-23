import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tokens and passwords stay in secure storage, never in Drift or a backup.
abstract class CloudSecretStore {
  static const github = 'koreanmemo.backup.github-token';
  static const webdav = 'koreanmemo.backup.webdav-password';

  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureCloudSecretStore implements CloudSecretStore {
  const SecureCloudSecretStore();

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
