import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class AiKeyStore {
  Future<String?> read();
  Future<void> write(String key);
  Future<void> delete();
}

/// Separate from Drift and its backup/restore snapshots.
class DeviceAiKeyStore implements AiKeyStore {
  static const _name = 'koreanmemo.deepseek.api-key';
  final _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  @override
  Future<String?> read() => _storage.read(key: _name);
  @override
  Future<void> write(String key) => _storage.write(key: _name, value: key);
  @override
  Future<void> delete() => _storage.delete(key: _name);
}

class AiKeyController extends StateNotifier<String> {
  AiKeyController(this.store) : super('') {
    ready = _load();
  }
  final AiKeyStore store;
  late final Future<void> ready;
  String? error;
  Future<void> _load() async {
    try {
      final key = await store.read();
      if (mounted) state = key ?? '';
    } catch (_) {
      error = '无法读取此设备保存的密钥，请重新填写或检查浏览器存储权限。';
    }
  }

  Future<void> save(String key) async {
    await ready;
    try {
      await store.write(key);
    } catch (_) {
      throw const FormatException('无法保存密钥，请检查此设备的存储权限后重试。');
    }
    if (mounted) {
      error = null;
      state = key;
    }
  }

  Future<void> clear() async {
    await ready;
    try {
      await store.delete();
    } catch (_) {
      throw const FormatException('无法清除已保存密钥，请检查存储权限后重试。');
    }
    if (mounted) {
      error = null;
      state = '';
    }
  }

  Future<String> current() async {
    await ready;
    return mounted ? state : '';
  }
}
