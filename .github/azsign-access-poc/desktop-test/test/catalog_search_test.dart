import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../flutter/lib/common/azsign/azsign_desktop_page.dart';
import '../../../../flutter/lib/common/azsign/azsign_http.dart';

class CatalogHttp extends AzsignHttp {
  CatalogHttp(Uri origin) : super(origin);
  final queries = <Map<String, String>>[];
  Completer<AzsignHttpResponse>? delayed;
  AzsignHttpResponse result(String name, int page) => AzsignHttpResponse(200, {
        'data': [
          {'id': 'device', 'name': name, 'tenant_id': 'tenant'}
        ],
        'meta': {
          'current_page': page,
          'last_page': 3,
          'per_page': 20,
          'total': 50
        }
      });
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
    queries.add(Map.of(query!));
    if (query['search'] == 'antiga') {
      delayed = Completer<AzsignHttpResponse>();
      return delayed!.future;
    }
    return result(query['search'] ?? 'Todos', int.parse(query['page']!));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'busca no CMS, mantém filtro ao paginar, descarta resposta antiga e limpa',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('org.rustdesk.rustdesk/host'),
        (call) async =>
            call.method == 'azsignSecureRead' ? 'test-token' : null);
    final http = CatalogHttp(Uri.parse('https://cms.example.test'));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AzsignDesktopPage(
                cmsOrigin: 'https://cms.example.test',
                httpFactory: (_) => http))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Loja  ');
    await tester.pump(const Duration(milliseconds: 299));
    expect(http.queries.length, 1);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(http.queries.last['search'], 'Loja');
    expect(http.queries.last['page'], '1');
    await tester.tap(find.text('Próxima'));
    await tester.pumpAndSettle();
    expect(http.queries.last['page'], '2');
    expect(http.queries.last['search'], 'Loja');
    await tester.enterText(find.byType(TextField), 'antiga');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'nova');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    http.delayed!.complete(http.result('Resultado antigo', 1));
    await tester.pumpAndSettle();
    expect(find.text('Resultado antigo'), findsNothing);
    expect(find.text('nova'), findsWidgets);
    await tester.tap(find.byTooltip('Limpar busca'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(http.queries.last.containsKey('search'), false);
    expect(http.queries.last['page'], '1');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
