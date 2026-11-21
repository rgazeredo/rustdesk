import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../flutter/lib/common/azsign/azsign_catalog_widgets.dart';
import '../../../../flutter/lib/common/azsign/azsign_desktop_page.dart';
import '../../../../flutter/lib/common/azsign/azsign_address_book_adapter.dart';
import '../../../../flutter/lib/common/azsign/azsign_http.dart';
import '../../../../flutter/lib/common/azsign/azsign_http_transports.dart';
import '../../../../flutter/lib/common/azsign/azsign_types.dart';
import 'catalog_search_test.dart' show CatalogHttp;

AddressBookDevice device(
        {bool provisioned = true,
        bool online = true,
        RemoteTransportStatus remote = RemoteTransportStatus.unknown}) =>
    AddressBookDevice(
        id: 'player',
        name: 'Recepção principal',
        tenantId: 'tenant',
        tenantName: 'Empresa',
        remoteId: '123456789',
        provisioned: provisioned,
        playerStatus: online
            ? PlayerHeartbeatStatus.online
            : PlayerHeartbeatStatus.offline,
        remoteAccessStatus: remote);

class StatusHttp extends CatalogHttp {
  StatusHttp() : super(Uri.parse('https://cms.example.test'));
  @override
  AzsignHttpResponse result(String name, int page) {
    final response = super.result(name, page);
    return AzsignHttpResponse(response.status, {
      ...response.data,
      'meta': <String, dynamic>{
        ...response.data['meta'] as Map<String, dynamic>,
        'supports_provisioning_filter': true
      }
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('provisioning is distinct from transport and supports older CMS data',
      () {
    expect(device(online: false).isProvisioned, true);
    final base = device().toJson()..remove('provisioned');
    expect(AddressBookDevice.fromJson(base).isProvisioned, true);
    expect(
        AddressBookDevice.fromJson({...base, 'remote_access_status': 'revoked'})
            .isProvisioned,
        false);
    expect(
        AddressBookDevice.fromJson({...base, 'provisioned': false})
            .isProvisioned,
        false);
    expect(
        const AzsignAddressBookFilter(
                provisioned: false, playerStatus: PlayerHeartbeatStatus.online)
            .toQueryParameters(),
        {'provisioned': '0', 'player_status': 'online'});
  });

  test('old CMS cannot silently ignore the provisioning filter', () async {
    final old = CatalogHttp(Uri.parse('https://cms.example.test'));
    final transport = AzsignHttpAddressBookTransport(old);
    await expectLater(
        transport.fetchCatalog(
            token: 'test-token',
            filter: const AzsignAddressBookFilter(provisioned: true)),
        throwsUnsupportedError);
    final current = AzsignHttpAddressBookTransport(StatusHttp());
    expect(
        (await current.fetchCatalog(
                token: 'test-token',
                filter: const AzsignAddressBookFilter(provisioned: false)))
            .pagination
            .total,
        50);
  });

  for (final width in [380.0, 1100.0]) {
    testWidgets('status cards remain legible and fit width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ListView(children: [
        AzsignPlayerCard(
            device: device(provisioned: false),
            onConnect: () => fail('Unprovisioned must not connect')),
        AzsignPlayerCard(device: device(online: false), onConnect: () {}),
        AzsignPlayerCard(
            device: device(remote: RemoteTransportStatus.blocked),
            onConnect: () => fail('Blocked must not connect')),
      ]))));
      expect(find.text('Não provisionado'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Acesso bloqueado'), findsOneWidget);
      expect(find.byIcon(Icons.verified_user_outlined), findsNWidgets(2));
      final buttons = tester
          .widgetList<OutlinedButton>(
              find.byWidgetPredicate((widget) => widget is OutlinedButton))
          .toList();
      expect(buttons[0].onPressed, isNull);
      expect(buttons[1].onPressed, isNotNull);
      expect(buttons[2].onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'both filters reset pagination and survive search, refresh and next page',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('org.rustdesk.rustdesk/host'),
        (call) async =>
            call.method == 'azsignSecureRead' ? '{"origin":"https://cms.example.test","value":"test-token"}' : null);
    final http = StatusHttp();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AzsignDesktopPage(
                cmsOrigin: 'https://cms.example.test',
                httpFactory: (_) => http))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Próxima'));
    await tester.pumpAndSettle();
    expect(http.queries.last['page'], '2');
    await tester.tap(find.byKey(const ValueKey('provisioning-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Provisionados').last);
    await tester.pumpAndSettle();
    expect(http.queries.last['page'], '1');
    expect(http.queries.last['provisioned'], '1');
    await tester.tap(find.byKey(const ValueKey('heartbeat-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offline').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Recepção');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Próxima'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atualizar'));
    await tester.pumpAndSettle();
    expect(http.queries.last, containsPair('provisioned', '1'));
    expect(http.queries.last, containsPair('player_status', 'offline'));
    expect(http.queries.last, containsPair('search', 'Recepção'));
    expect(http.queries.last['page'], '2');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
