import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../flutter/lib/common/azsign/azsign_desktop_page.dart';
import '../../../../flutter/lib/common/azsign/azsign_http.dart';
import 'deep_link_test.dart' show LinkHttp;

class RecoveredCatalogHttp extends LinkHttp {
  int reads = 0;
  bool removed = false;
  bool unavailable = false;
  @override
  Future<AzsignHttpResponse> request(String method, String path,
      {String? token, Map<String, dynamic>? body, Map<String, String>? query}) async {
    if (!path.endsWith('/address-book')) {
      return super.request(method, path, token: token, body: body, query: query);
    }
    reads++;
    if (unavailable && reads > 1) return const AzsignHttpResponse(503, {});
    return AzsignHttpResponse(200, {
      'data': removed && reads > 1 ? [] : [{
        'id': 'same-player', 'name': 'DC400xx', 'tenant_id': 'tenant',
        'remote_id': reads == 1 ? '1865846518' : '1293024870',
        'player_status': 'online', 'remote_access_status': 'unknown',
      }],
      'meta': {'current_page': 1, 'last_page': 1, 'per_page': 20, 'total': 1},
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final failure in ['none', 'removed', 'unavailable']) {
    testWidgets('catalog connection rechecks recovered binding: $failure', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('org.rustdesk.rustdesk/host'), (call) async {
        if (call.method == 'azsignSecureRead') return 'bearer';
        if (call.method == 'azsignNativeTransportAvailable') return true;
        if (call.method == 'azsignIdentityPrepare') return {'identity_id': 'identity', 'csr': 'public CSR'};
        return null;
      });
      final http = RecoveredCatalogHttp()
        ..removed = failure == 'removed'
        ..unavailable = failure == 'unavailable';
      final connections = <String>[];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AzsignDesktopPage(
        cmsOrigin: 'https://cms.example.test', httpFactory: (_) => http,
        onConnect: (_, id) async { connections.add(id); },
      ))));
      await tester.pumpAndSettle();
      expect(find.textContaining('1865846518'), findsOneWidget);
      await tester.tap(find.text('Conectar'));
      await tester.pumpAndSettle();
      expect(connections, failure == 'none' ? ['1293024870'] : isEmpty);
      if (failure == 'none') expect(find.textContaining('1293024870'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
