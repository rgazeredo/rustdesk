import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'azsign_types.dart';

/// Exception thrown when native OS secure storage (Keychain / DPAPI) is unavailable.
/// We strictly forbid silent fallback to plaintext files.
class SecureStorageUnavailableException implements Exception {
  final String message;
  const SecureStorageUnavailableException(this.message);
  @override
  String toString() => 'SecureStorageUnavailableException: $message';
}

/// Abstract contract for OS secure storage (Keychain on macOS, DPAPI on Windows, SecretService on Linux).
abstract class AzsignSecureStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// In-memory secure storage implementation for test harnesses and unit testing.
class InMemorySecureStorage implements AzsignSecureStorage {
  final Map<String, String> _storage = {};

  @override
  Future<String?> read(String key) async => _storage[key];

  @override
  Future<void> write(String key, String value) async => _storage[key] = value;

  @override
  Future<void> delete(String key) async => _storage.remove(key);
}

/// PKCE Challenge and Verifier generator (RFC 7636).
class AzsignPkce {
  final String verifier;
  final String challenge;

  AzsignPkce({required this.verifier, required this.challenge});

  static AzsignPkce generate() {
    final random = Random.secure();
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = random.nextInt(256);
    }
    final verifier = base64Url.encode(bytes).replaceAll('=', '');
    final hash = sha256.convert(utf8.encode(verifier));
    final challenge = base64Url.encode(hash.bytes).replaceAll('=', '');
    return AzsignPkce(verifier: verifier, challenge: challenge);
  }
}

class AzsignAuthorizationRequest {
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;

  const AzsignAuthorizationRequest({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    this.interval = 3,
  });
}

enum TokenPollStatus {
  pending,
  slowDown,
  expired,
  denied,
  approved,
}

class AzsignTokenPollResult {
  final TokenPollStatus status;
  final AzsignSession? session;
  final String? errorMessage;

  const AzsignTokenPollResult({
    required this.status,
    this.session,
    this.errorMessage,
  });
}

/// Transport interface for desktop browser authorization (device code + PKCE).
/// Decouples the UI and state management from the concrete HTTP endpoints.
abstract class AzsignAuthTransport {
  Future<AzsignAuthorizationRequest> requestAuthorization({
    required String codeChallenge,
    required String deviceId,
    required String deviceLabel,
    String? clientVersion,
  });

  Future<AzsignTokenPollResult> pollToken({
    required String deviceCode,
    required String codeVerifier,
  });

  Future<AzsignSession?> fetchSession(String token);

  Future<void> revokeSession(String token);
}

/// Desktop authentication service managing login lifecycle, PKCE, secure storage,
/// and single-use device code polling without receiving user passwords in the app.
class AzsignAuthService {
  final AzsignAuthTransport transport;
  final AzsignSecureStorage secureStorage;

  AzsignAuthService({
    required this.transport,
    required this.secureStorage,
  });

  static const String _kDeviceIdKey = 'azsign_desktop_device_id';
  static const String _kTokenKey = 'azsign_desktop_access_token';

  String? _pendingDeviceCode;
  String? _pendingVerifier;
  DateTime? _pendingExpiresAt;

  /// Ensures a stable, random RFC 4122 v4 UUID is generated per desktop installation.
  Future<String> getOrCreateDeviceId() async {
    final existing = await secureStorage.read(_kDeviceIdKey);
    if (existing != null && _isValidUuid(existing)) {
      return existing;
    }
    final newId = _generateUuidV4();
    await secureStorage.write(_kDeviceIdKey, newId);
    return newId;
  }

  /// Starts the browser-based authorization flow with PKCE.
  /// Never prompts for or touches user password in the client.
  Future<AzsignAuthorizationRequest> startLogin({
    String? deviceLabel,
    String? clientVersion,
  }) async {
    final deviceId = await getOrCreateDeviceId();
    final pkce = AzsignPkce.generate();

    final authRequest = await transport.requestAuthorization(
      codeChallenge: pkce.challenge,
      deviceId: deviceId,
      deviceLabel: deviceLabel ?? 'AZSign Desktop Operator',
      clientVersion: clientVersion,
    );

    _pendingDeviceCode = authRequest.deviceCode;
    _pendingVerifier = pkce.verifier;
    _pendingExpiresAt = DateTime.now().add(Duration(seconds: authRequest.expiresIn));

    // Open system browser with safe verification URI
    if (await canLaunchUrlString(authRequest.verificationUri)) {
      await launchUrlString(authRequest.verificationUri, mode: LaunchMode.externalApplication);
    }

    return authRequest;
  }

  /// Single attempt to exchange pending device code for bearer token.
  Future<AzsignTokenPollResult> pollLogin() async {
    final deviceCode = _pendingDeviceCode;
    final verifier = _pendingVerifier;
    final expiresAt = _pendingExpiresAt;

    if (deviceCode == null || verifier == null || expiresAt == null) {
      return const AzsignTokenPollResult(
        status: TokenPollStatus.expired,
        errorMessage: 'Nenhum login em andamento.',
      );
    }

    if (DateTime.now().isAfter(expiresAt)) {
      _clearPending();
      return const AzsignTokenPollResult(
        status: TokenPollStatus.expired,
        errorMessage: 'A autorização expirou no navegador. Inicie novamente.',
      );
    }

    final result = await transport.pollToken(
      deviceCode: deviceCode,
      codeVerifier: verifier,
    );

    if (result.status == TokenPollStatus.approved && result.session != null) {
      await secureStorage.write(_kTokenKey, result.session!.token);
      _clearPending();
    } else if (result.status == TokenPollStatus.expired || result.status == TokenPollStatus.denied) {
      _clearPending();
    }

    return result;
  }

  /// Checks if an active session exists in secure storage and validates it against CMS.
  Future<AzsignSession?> checkSession() async {
    final token = await secureStorage.read(_kTokenKey);
    if (token == null || token.isEmpty) return null;

    try {
      final session = await transport.fetchSession(token);
      if (session == null || session.isExpired) {
        await secureStorage.delete(_kTokenKey);
        return null;
      }
      return session;
    } catch (_) {
      // On network error or rejection, do not trust invalid token
      await secureStorage.delete(_kTokenKey);
      return null;
    }
  }

  /// Clean logout: revokes token on CMS and removes from secure storage.
  Future<void> logout() async {
    final token = await secureStorage.read(_kTokenKey);
    if (token != null && token.isNotEmpty) {
      try {
        await transport.revokeSession(token);
      } catch (_) {
        // Continue clearing local storage even if network revoke fails
      }
      await secureStorage.delete(_kTokenKey);
    }
    _clearPending();
  }

  void _clearPending() {
    _pendingDeviceCode = null;
    _pendingVerifier = null;
    _pendingExpiresAt = null;
  }

  static bool _isValidUuid(String value) {
    return RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', caseSensitive: false)
        .hasMatch(value);
  }

  static String _generateUuidV4() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40; // Version 4
    values[8] = (values[8] & 0x3f) | 0x80; // Variant 10
    final hex = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }
}
