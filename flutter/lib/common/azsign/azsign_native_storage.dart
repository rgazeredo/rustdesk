import 'dart:io';
import 'package:flutter/services.dart';
import 'azsign_auth_adapter.dart';
import 'azsign_native_channel.dart';

class AzsignNativeStorage implements AzsignSecureStorage {
  static const _channel = MethodChannel('org.rustdesk.rustdesk/host');

  Future<T?> _invoke<T>(String method, String key, [String? value]) async {
    if (!Platform.isMacOS && !Platform.isWindows) {
      throw const SecureStorageUnavailableException(
          'Armazenamento seguro indisponível nesta plataforma.');
    }
    try {
      return await azsignNativeInvoke<T>(
          _channel, method, {'key': key, if (value != null) 'value': value});
    } on PlatformException {
      throw const SecureStorageUnavailableException(
          'Não foi possível acessar o armazenamento seguro.');
    } on MissingPluginException {
      throw const SecureStorageUnavailableException(
          'Build sem armazenamento seguro AZSign.');
    }
  }

  @override
  Future<String?> read(String key) => _invoke<String>('azsignSecureRead', key);
  @override
  Future<void> write(String key, String value) async {
    await _invoke<void>('azsignSecureWrite', key, value);
  }

  @override
  Future<void> delete(String key) async {
    await _invoke<void>('azsignSecureDelete', key);
  }
}
