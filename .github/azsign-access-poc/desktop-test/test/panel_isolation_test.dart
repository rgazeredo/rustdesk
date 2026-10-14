import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../flutter/lib/common/azsign/azsign_auth_adapter.dart';
import '../../../../flutter/lib/common/azsign/azsign_installation.dart';
import '../../../../flutter/lib/common/azsign/azsign_panel_storage.dart';
import '../../../../flutter/lib/common/azsign/azsign_panel_page.dart';
import '../../../../flutter/lib/common/azsign/azsign_deep_link.dart';
import '../../../../flutter/lib/common/azsign/azsign_desktop_page.dart';
import 'deep_link_test.dart' show LinkHttp;

class MemoryStorage implements AzsignSecureStorage {
  final values = <String, String>{};
  Future<String?> read(String key) async => values[key];
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class Discovery extends AzsignInstallationDiscovery {
  Future<AzsignInstallation> discover(String domain) async =>
      AzsignInstallation(
          domain, 'AHS Tech LED', Uri.parse('https://api.partner.example'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    azsignRequestedRemoteId.value = null;
    azsignRequestedPanelDomain = null;
  });
  test('secure records cannot cross origins or erase another origin', () async {
    final storage = MemoryStorage();
    final a = AzsignPanelStorage(storage, Uri.parse(azsignCentralOrigin));
    final b =
        AzsignPanelStorage(storage, Uri.parse('https://api.partner.example'));
    await a.write('token', 'primary');
    expect(await b.read('token'), isNull);
    await b.delete('token');
    expect(await a.read('token'), 'primary');
    await b.write('token', 'partner');
    expect(await a.read('token'), isNull);
    expect(await b.read('token'), 'partner');
    storage.values['legacy'] = 'old-bearer';
    expect(await b.read('legacy'), isNull);
    expect(await a.read('legacy'), 'old-bearer');
  });
  test('catalog binds requested domain and rejects unsafe API origins', () {
    Map<String, dynamic> payload(String origin) => {
          'data': {
            'id': 'installation',
            'type': 'independent',
            'name': 'AHS Tech LED',
            'domain': 'panel.partner.example',
            'api_base_url': origin,
          }
        };
    expect(
        AzsignInstallation.fromDiscovery(
                'panel.partner.example', payload('https://api.partner.example'))
            .origin
            .host,
        'api.partner.example');
    expect(
        () => AzsignInstallation.fromDiscovery(
            'other.example', payload('https://api.partner.example')),
        throwsFormatException);
    for (final origin in [
      'http://api.partner.example',
      'https://user@api.partner.example',
      'https://api.partner.example/path',
      'https://api.partner.example:8443',
      'https://127.0.0.1',
      'https://api.partner.example?token=secret'
    ]) {
      expect(
          () => AzsignInstallation.fromDiscovery(
              'panel.partner.example', payload(origin)),
          throwsFormatException);
    }
  });
  test('panel-qualified links accept only one normalized domain', () {
    expect(
        azsignRemoteIdFromLink(Uri.parse(
            'azsign-remote://connection/new/123456?panel=panel.partner.example')),
        '123456');
    for (final query in [
      'panel=https://evil.example',
      'panel=a.example&panel=b.example',
      'panel=a.example&token=x',
      'panel='
    ]) {
      expect(
          azsignRemoteIdFromLink(
              Uri.parse('azsign-remote://connection/new/123456?$query')),
          isNull);
    }
  });
  testWidgets('a link from another panel never enrolls or connects',
      (tester) async {
    final storage = MemoryStorage();
    await AzsignPanelStorage(storage, Uri.parse(azsignCentralOrigin))
        .write('azsign_desktop_access_token', 'bearer');
    final http = LinkHttp();
    final connections = <String>[];
    azsignRequestedPanelDomain = 'panel.partner.example';
    azsignRequestedRemoteId.value = '123456';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AzsignDesktopPage(
      cmsOrigin: azsignCentralOrigin,
      secureStorage: storage,
      httpFactory: (_) => http,
      onConnect: (_, id) async {
        connections.add(id);
      },
    ))));
    await tester.pumpAndSettle();
    expect(connections, isEmpty);
    expect(http.calls, isEmpty);
    expect(find.textContaining('Troque de painel'), findsOneWidget);
  });
  testWidgets('switch clears native access before selecting a partner',
      (tester) async {
    final storage = MemoryStorage();
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('org.rustdesk.rustdesk/host'), (call) async {
      calls.add(call.method);
      return null;
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AzsignPanelPage(
      defaultOrigin: azsignCentralOrigin,
      storage: storage,
      discovery: Discovery(),
      httpFactory: (_) => LinkHttp(),
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trocar painel'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'panel.partner.example');
    await tester.tap(find.text('Usar este painel'));
    await tester.pumpAndSettle();
    expect(find.text('AHS Tech LED'), findsOneWidget);
    expect(calls.where((method) => method == 'azsignIdentityClear').length, 3);
    expect(jsonDecode(storage.values['azsign_desktop_panel']!)['origin'],
        'https://api.partner.example');
  });
  testWidgets('failed native cleanup prevents opening another panel',
      (tester) async {
    final storage = MemoryStorage();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('org.rustdesk.rustdesk/host'), (call) async {
      if (call.method == 'azsignIdentityClear')
        throw PlatformException(code: 'unavailable');
      return null;
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AzsignPanelPage(
      defaultOrigin: azsignCentralOrigin,
      storage: storage,
      discovery: Discovery(),
      httpFactory: (_) => LinkHttp(),
    ))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'panel.partner.example');
    await tester.tap(find.text('Usar este painel'));
    await tester.pumpAndSettle();
    expect(find.text('AHS Tech LED'), findsNothing);
    expect(storage.values['azsign_desktop_panel'], isNull);
    expect(find.textContaining('Painel indisponível'), findsOneWidget);
  });

  testWidgets('changed discovery origin requires explicit reselection',
      (tester) async {
    final storage = MemoryStorage();
    storage.values['azsign_desktop_panel'] = jsonEncode({
      'domain': 'panel.partner.example',
      'origin': 'https://old.partner.example',
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('org.rustdesk.rustdesk/host'),
        (call) async => null);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AzsignPanelPage(
      defaultOrigin: azsignCentralOrigin,
      storage: storage,
      discovery: Discovery(),
      httpFactory: (_) => throw StateError('Must not contact changed API'),
    ))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Não foi possível validar'), findsOneWidget);
    expect(find.text('AHS Tech LED'), findsNothing);
  });
}
