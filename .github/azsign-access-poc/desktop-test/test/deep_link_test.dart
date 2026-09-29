import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../flutter/lib/common/azsign/azsign_deep_link.dart';
import '../../../../flutter/lib/common/azsign/azsign_desktop_page.dart';
import '../../../../flutter/lib/common/azsign/azsign_http.dart';
import 'desktop_test.dart' show EnrollmentHttp;

class LinkHttp extends EnrollmentHttp {
  bool deny = false;
  @override
  Future<AzsignHttpResponse> request(String method, String path,
      {String? token,
      Map<String, dynamic>? body,
      Map<String, String>? query}) async {
    if (path.endsWith('/session'))
      return AzsignHttpResponse(200, {
        'expires_at':
            DateTime.now().add(const Duration(days: 1)).toIso8601String(),
        'user': {'id': 'user', 'name': 'Admin', 'email': 'user@example.test'},
        'tenant': {'id': 'tenant', 'name': 'VTM'}
      });
    if (path.endsWith('/address-book'))
      return const AzsignHttpResponse(200, {
        'data': [],
        'meta': {'current_page': 1, 'last_page': 1, 'per_page': 20, 'total': 0}
      });
    if (deny) return const AzsignHttpResponse(403, {});
    return super.request(method, path, token: token, body: body, query: query);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => azsignRequestedRemoteId.value = null);
  for (final denied in [false, true]) {
    testWidgets(
        'confirmed link uses enrollment and refuses denied CMS: $denied',
        (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('org.rustdesk.rustdesk/host'), (call) async {
        if (call.method == 'azsignSecureRead') return 'bearer';
        if (call.method == 'azsignNativeTransportAvailable') return true;
        if (call.method == 'azsignIdentityPrepare')
          return {'identity_id': 'identity', 'csr': 'public CSR'};
        return null;
      });
      final http = LinkHttp()..deny = denied;
      final connections = <String>[];
      azsignRequestedRemoteId.value = '1465886383';
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: AzsignDesktopPage(
                  cmsOrigin: 'https://cms.example.test',
                  httpFactory: (_) => http,
                  onConnect: (_, id) async {
                    connections.add(id);
                  }))));
      await tester.pumpAndSettle();
      expect(connections, isEmpty);
      await tester.tap(find.text('Conectar ao player'));
      await tester.pumpAndSettle();
      expect(connections, denied ? isEmpty : ['1465886383']);
      if (!denied) expect(http.calls.length, 3);
      azsignRequestedRemoteId.value = '1865846518';
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sair'));
      await tester.pumpAndSettle();
      expect(azsignRequestedRemoteId.value, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  test('accepts only a connection target, not credentials or server settings',
      () {
    expect(
        azsignRemoteIdFromLink(
            Uri.parse('azsign-remote://connection/new/1465886383')),
        '1465886383');
    for (final link in [
      'rustdesk://connection/new/1465886383',
      'azsign-remote://config/evil',
      'azsign-remote://connection/new/1465886383?password=secret',
      'azsign-remote://connection/new/1465886383?key=evil',
      'azsign-remote://connection/new/1465886383#fragment',
      'azsign-remote://user@connection/new/1465886383',
      'azsign-remote://connection:42/new/1465886383',
      'azsign-remote://connection/new/id@server',
      'azsign-remote://connection/new/123',
    ]) {
      expect(azsignRemoteIdFromLink(Uri.parse(link)), isNull, reason: link);
    }
  });
  testWidgets('cold link remains pending and cannot connect before login',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('org.rustdesk.rustdesk/host'),
        (call) async => null);
    var connections = 0;
    azsignRequestedRemoteId.value = '1465886383';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AzsignDesktopPage(
                cmsOrigin: 'https://cms.example.test',
                onConnect: (_, __) async {
                  connections++;
                }))));
    await tester.pumpAndSettle();
    expect(find.text('Solicitação do painel: 1465886383'), findsOneWidget);
    expect(
        tester
            .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Conectar ao player'))
            .onPressed,
        isNull);
    expect(connections, 0);
    azsignRequestedRemoteId.value = '1865846518';
    await tester.pumpAndSettle();
    expect(find.text('Solicitação do painel: 1865846518'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(azsignRequestedRemoteId.value, isNull);
    expect(connections, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
