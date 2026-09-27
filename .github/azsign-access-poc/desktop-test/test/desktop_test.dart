import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../flutter/lib/common/azsign/azsign_desktop_page.dart';
import '../../../../flutter/lib/common/azsign/azsign_auth_adapter.dart';
import '../../../../flutter/lib/common/azsign/azsign_types.dart';
import '../../../../flutter/lib/common/azsign/azsign_native_enrollment.dart';
import '../../../../flutter/lib/common/azsign/azsign_http.dart';
import 'dart:async';
import 'dart:convert';

class EnrollmentHttp extends AzsignHttp {
  final calls = <String>[];
  Completer<void>? certificateWait;
  bool wrongIdentity = false;
  EnrollmentHttp() : super(Uri.parse('https://app.azsign.com.br'));
  @override
  Future<AzsignHttpResponse> request(String method, String path,
      {String? token,
      Map<String, dynamic>? body,
      Map<String, String>? query}) async {
    calls.add(path);
    expect(token, 'bearer');
    if (path.endsWith('/certificate')) {
      expect(body, {'csr': 'public CSR'});
      await certificateWait?.future;
      return AzsignHttpResponse(200, {
        'identity_id': wrongIdentity ? 'other' : 'identity',
        'certificate': 'public PEM',
        'expires_at': '2026-09-29T00:00:00Z',
        'session_expires_at': '2026-09-29T00:00:00Z'
      });
    }
    if (path.endsWith('/profile'))
      return AzsignHttpResponse(200, {
        'protocol': 2,
        'identity_id': 'identity',
        'installation_id': 'installation',
        'profile': {'host': 'gateway.example'},
        'ca_certificate': 'public CA',
        'server_public_key': base64Encode(List.filled(32, 1)),
        'session_expires_at': '2026-09-29T00:00:00Z'
      });
    return const AzsignHttpResponse(
        200, {'identity_id': 'identity', 'installation_id': 'installation'});
  }
}

class FailingTransport implements AzsignAuthTransport {
  bool revokeFails = false;
  @override
  Future<AzsignSession?> fetchSession(String token) async =>
      throw StateError('Network offline');
  @override
  Future<void> revokeSession(String token) async {
    if (revokeFails) throw StateError('Network offline');
  }

  @override
  Future<AzsignAuthorizationRequest> requestAuthorization(
          {required String codeChallenge,
          required String deviceId,
          required String deviceLabel,
          String? clientVersion}) =>
      throw UnimplementedError();
  @override
  Future<AzsignTokenPollResult> pollToken(
          {required String deviceCode, required String codeVerifier}) =>
      throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.rustdesk.rustdesk/host');
  test(
      'native enrollment exchanges only CSR/public certificate and checks capability',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'azsignNativeTransportAvailable') return true;
      if (call.method == 'azsignIdentityPrepare')
        return {'identity_id': 'identity', 'csr': 'public CSR'};
      return null;
    });
    final http = EnrollmentHttp();
    addTearDown(http.close);
    final enrollment = AzsignNativeEnrollment(http);
    await enrollment.provision('bearer');
    expect(calls.map((call) => call.method), [
      'azsignNativeTransportAvailable',
      'azsignIdentityPrepare',
      'azsignIdentityInstall'
    ]);
    expect((calls.last.arguments as Map).containsKey('private_pkcs8'), false);
    expect(http.calls.length, 3);
  });
  test('logout during issuance cannot install a late certificate', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'azsignNativeTransportAvailable') return true;
      if (call.method == 'azsignIdentityPrepare')
        return {'identity_id': 'identity', 'csr': 'public CSR'};
      return null;
    });
    final http = EnrollmentHttp()..certificateWait = Completer<void>();
    addTearDown(http.close);
    final enrollment = AzsignNativeEnrollment(http);
    final pending = enrollment.provision('bearer');
    final rejection = expectLater(pending, throwsStateError);
    while (http.calls.length < 3) {
      await Future<void>.delayed(Duration.zero);
    }
    await enrollment.clear();
    http.certificateWait!.complete();
    await rejection;
    expect(calls, isNot(contains('azsignIdentityInstall')));
  });
  test('ordinary RustDesk build cannot enable the native connection', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => false);
    final http = EnrollmentHttp();
    addTearDown(http.close);
    await expectLater(
        AzsignNativeEnrollment(http).provision('bearer'), throwsStateError);
    expect(http.calls, isEmpty);
  });
  test('network failure does not destroy the token or authenticate offline',
      () async {
    final storage = InMemorySecureStorage();
    await storage.write('azsign_desktop_access_token', 'secret');
    final auth = AzsignAuthService(
        transport: FailingTransport(), secureStorage: storage);
    await expectLater(auth.checkSession(), throwsStateError);
    expect(await storage.read('azsign_desktop_access_token'), 'secret');
  });
  test('logout clears local token and reports failed server revocation',
      () async {
    final storage = InMemorySecureStorage();
    await storage.write('azsign_desktop_access_token', 'secret');
    final transport = FailingTransport()..revokeFails = true;
    final auth =
        AzsignAuthService(transport: transport, secureStorage: storage);
    await expectLater(auth.logout(), throwsStateError);
    expect(await storage.read('azsign_desktop_access_token'), isNull);
  });
  test('device UUID remains stable and PKCE verifier changes each attempt',
      () async {
    final auth = AzsignAuthService(
        transport: FailingTransport(), secureStorage: InMemorySecureStorage());
    expect(await auth.getOrCreateDeviceId(), await auth.getOrCreateDeviceId());
    final pkce = AzsignPkce.generate();
    expect(pkce.verifier.length, 43);
    expect(pkce.challenge.length, 43);
    expect(AzsignPkce.generate().verifier, isNot(pkce.verifier));
  });
  testWidgets(
      'real desktop page renders browser login without a password field',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('org.rustdesk.rustdesk/host'),
        (call) async => null);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: AzsignDesktopPage(cmsOrigin: 'https://app.azsign.com.br'))));
    await tester.pumpAndSettle();
    expect(find.text('Entrar com AZSign'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
