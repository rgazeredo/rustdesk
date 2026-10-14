import 'dart:convert';
import 'azsign_auth_adapter.dart';
import 'azsign_installation.dart';

/// Only one panel is active. Each secure record is bound to its HTTPS origin;
/// a token from another panel is never returned to an HTTP transport.
class AzsignPanelStorage implements AzsignSecureStorage {
  final AzsignSecureStorage storage;
  final String origin;
  AzsignPanelStorage(this.storage, Uri origin) : origin = origin.origin;

  @override
  Future<String?> read(String key) async {
    final raw = await storage.read(key);
    if (raw == null) return null;
    try {
      final record = jsonDecode(raw);
      if (record is Map<String, dynamic> &&
          record['origin'] == origin &&
          record['value'] is String) return record['value'] as String;
      return null;
    } on FormatException {
      // Previous public builds stored unscoped records for the AZSign CMS.
      // Never migrate these credentials to a partner endpoint.
      if (origin != azsignCentralOrigin) return null;
      await write(key, raw);
      return raw;
    }
  }

  @override
  Future<void> write(String key, String value) =>
      storage.write(key, jsonEncode({'origin': origin, 'value': value}));

  @override
  Future<void> delete(String key) async {
    if (await read(key) != null) await storage.delete(key);
  }
}
