import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../flutter/lib/common/azsign/azsign_desktop_page.dart';
import '../../../../flutter/lib/common/azsign/azsign_http.dart';
import 'catalog_search_test.dart' show CatalogHttp;

class PreviewHttp extends CatalogHttp {
  PreviewHttp() : super(Uri.parse('https://cms.example.test'));
  @override
  AzsignHttpResponse result(String name, int page) =>
      const AzsignHttpResponse(200, {
        'data': [
          {
            'id': 'reception',
            'name': 'Recepção principal',
            'tenant_id': 'tenant',
            'tenant_name': 'Empresa',
            'remote_id': '123456789',
            'provisioned': true,
            'player_status': 'online',
            'remote_access_status': 'unknown'
          },
          {
            'id': 'window',
            'name': 'Vitrine · Loja Centro',
            'tenant_id': 'tenant',
            'tenant_name': 'Empresa',
            'remote_id': '234567890',
            'provisioned': true,
            'player_status': 'offline',
            'remote_access_status': 'unknown'
          },
          {
            'id': 'entrance',
            'name': 'Totem de entrada',
            'tenant_id': 'tenant',
            'tenant_name': 'Empresa',
            'provisioned': false,
            'player_status': 'online',
            'remote_access_status': 'unprovisioned'
          },
          {
            'id': 'checkout',
            'name': 'Caixa · Loja Norte',
            'tenant_id': 'tenant',
            'tenant_name': 'Empresa',
            'remote_id': '345678901',
            'provisioned': true,
            'player_status': 'online',
            'remote_access_status': 'blocked'
          },
        ],
        'meta': {
          'current_page': 1,
          'last_page': 1,
          'per_page': 20,
          'total': 4,
          'supports_provisioning_filter': true
        }
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final sdk = Platform.environment['AZSIGN_PREVIEW_FLUTTER_SDK'];
    if (sdk == null) return;
    final fonts = '$sdk/bin/cache/artifacts/material_fonts';
    final roboto = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      roboto.addFont(File('$fonts/Roboto-$weight.ttf')
          .readAsBytes()
          .then((bytes) => ByteData.view(bytes.buffer)));
    }
    await roboto.load();
    await (FontLoader('MaterialIcons')
          ..addFont(File('$fonts/MaterialIcons-Regular.otf')
              .readAsBytes()
              .then((bytes) => ByteData.view(bytes.buffer))))
        .load();
  });
  for (final width in [800.0, 1200.0]) {
    testWidgets('catalog screen fits desktop width $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('org.rustdesk.rustdesk/host'),
          (call) async =>
              call.method == 'azsignSecureRead' ? '{"origin":"https://cms.example.test","value":"test-token"}' : null);
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                  useMaterial3: false,
                  scaffoldBackgroundColor: Colors.white,
                  colorScheme: const ColorScheme.light(primary: Colors.blue)),
              home: Scaffold(
                  body: AzsignDesktopPage(
                      cmsOrigin: 'https://cms.example.test',
                      httpFactory: (_) => PreviewHttp(),
                      onConnect: (_, __) async {})))));
      await tester.pumpAndSettle();
      expect(find.text('Não provisionado'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Acesso bloqueado'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final output = Platform.environment['AZSIGN_CATALOG_PREVIEW_DIR'];
      if (output != null) {
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/catalog-${width.toInt()}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
