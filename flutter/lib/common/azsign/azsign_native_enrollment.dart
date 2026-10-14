import 'dart:convert';
import 'package:flutter/services.dart';
import 'azsign_http.dart';
import 'azsign_native_channel.dart';

/// The channel exchanges public data only. Private keys remain native/Keychain.
class AzsignNativeEnrollment {
  final AzsignHttp http;
  final MethodChannel channel;
  int _generation = 0;
  Future<void> _nativeTail = Future.value();

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? arguments]) {
    final result = _nativeTail
        .then((_) => azsignNativeInvoke<T>(channel, method, arguments));
    _nativeTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  AzsignNativeEnrollment(this.http,
      {this.channel = const MethodChannel('org.rustdesk.rustdesk/host')});

  Future<void> clear() async {
    _generation++;
    await _invoke<dynamic>('azsignIdentityClear');
  }

  Future<Map<String, dynamic>> provision(String token) async {
    final generation = ++_generation;
    void current() {
      if (generation != _generation) throw StateError('Enrollment cancelled');
    }

    if (await _invoke<bool>('azsignNativeTransportAvailable') != true) {
      throw StateError('Build has no authenticated native transport');
    }
    current();
    final identityResponse =
        await http.request('POST', '/api/v1/desktop/enrollment', token: token);
    identityResponse.requireSuccess();
    current();
    final identity = identityResponse.data['identity_id'] as String;
    final profileResponse = await http
        .request('GET', '/api/v1/desktop/enrollment/profile', token: token);
    profileResponse.requireSuccess();
    current();
    final profile = profileResponse.data;
    if (profile['protocol'] != 2 ||
        profile['identity_id'] != identity ||
        profile['installation_id'] !=
            identityResponse.data['installation_id'] ||
        base64Decode(profile['server_public_key'] as String).length != 32) {
      throw const FormatException('Invalid enrollment profile');
    }
    final prepared = await _invoke<dynamic>(
        'azsignIdentityPrepare', {'identity_id': identity});
    current();
    if (prepared?['identity_id'] != identity) {
      throw StateError('Identity mismatch');
    }
    final response = await http.request(
        'POST', '/api/v1/desktop/enrollment/certificate',
        token: token, body: {'csr': prepared!['csr'] as String});
    response.requireSuccess();
    current();
    if (response.data['identity_id'] != identity ||
        response.data['session_expires_at'] != profile['session_expires_at']) {
      throw const FormatException('Certificate session mismatch');
    }
    await _invoke<dynamic>('azsignIdentityInstall', {
      ...profile,
      ...response.data,
    });
    current();
    return profile;
  }
}
