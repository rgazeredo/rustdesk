import 'dart:convert';
import 'dart:io';
import '../../flutter/lib/common/azsign/azsign_http.dart';
import '../../flutter/lib/common/azsign/azsign_types.dart';
import '../../flutter/lib/common/azsign/azsign_http_transports.dart';
import '../../flutter/lib/common/azsign/azsign_auth_transport.dart';

void check(bool value, String label) {
  if (!value) throw StateError(label);
  stdout.writeln('PASS $label');
}

Future<void> rejects(Future<void> Function() action, String label) async {
  var rejected = false;
  try {
    await action();
  } catch (_) {
    rejected = true;
  }
  check(rejected, label);
}

Future<void> main(List<String> args) async {
  final serverContext = SecurityContext()
    ..useCertificateChain(args[0])
    ..usePrivateKey(args[1]);
  final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4, 0, serverContext);
  var requests = 0;
  server.listen((request) async {
    requests++;
    final mode = request.uri.queryParameters['mode'];
    if (request.uri.path == '/api/v1/desktop/authorizations/token') {
      final input = jsonDecode(await utf8.decoder.bind(request).join());
      request.response.headers.contentType = ContentType.json;
      request.response.statusCode = int.parse(input['device_code']);
      request.response.write(jsonEncode({'status': 'pending'}));
    } else if (mode == 'redirect') {
      request.response.statusCode = 302;
      request.response.headers.set('location', '/api/v1/desktop/stolen');
    } else if (mode == 'html') {
      request.response.headers.contentType = ContentType.html;
      request.response.write('<html>login</html>');
    } else {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'authorization': request.headers.value('authorization'),
        'body': await utf8.decoder.bind(request).join(),
        'padding': mode == 'oversized' ? 'x' * AzsignHttp.maxResponseBytes : '',
      }));
    }
    await request.response.close();
  });
  final origin = Uri.parse('https://127.0.0.1:${server.port}');
  final clientContext = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificates(args[0]);
  final http = AzsignHttp(origin, client: HttpClient(context: clientContext));
  try {
    final response = await http.request(
        'POST', '/api/v1/desktop/authorizations',
        token: 'test-token', body: {'code_verifier': 'test-verifier'});
    check(response.data['authorization'] == 'Bearer test-token',
        'Bearer sent only to configured HTTPS origin');
    check(jsonDecode(response.data['body'])['code_verifier'] == 'test-verifier',
        'JSON request crosses real TLS socket');
    final before = requests;
    await rejects(() async {
      await http.request('GET', '/api/v1/desktop/session',
          query: {'mode': 'redirect'});
    }, 'redirect rejected');
    check(requests == before + 1, 'redirect never followed');
    await rejects(() async {
      await http
          .request('GET', '/api/v1/desktop/session', query: {'mode': 'html'});
    }, 'HTML response rejected');
    await rejects(() async {
      await http.request('GET', '/api/v1/desktop/session',
          query: {'mode': 'oversized'});
    }, 'oversized response rejected');
    await rejects(() async {
      http.verificationUri(
          'https://evil.example/desktop/authorize/00000000-0000-0000-0000-000000000000');
    }, 'foreign browser origin rejected');
    await rejects(() async {
      AzsignHttp(Uri.parse('http://localhost'));
    }, 'plaintext CMS rejected');
    final untrusted = AzsignHttp(origin,
        client: HttpClient(context: SecurityContext(withTrustedRoots: false)));
    try {
      await rejects(() async {
        await untrusted.request('GET', '/api/v1/desktop/session');
      }, 'untrusted TLS certificate rejected');
    } finally {
      untrusted.close();
    }
    final session = AzsignSession.fromJson({
      'expires_at': '2026-01-01T00:00:00Z',
      'expires_in': 86400,
      'user': {'id': 'u', 'name': 'n', 'email': 'e'},
      'tenant': {'id': 't', 'name': 'tenant'},
    }, existingToken: 'existing');
    check(
        session.token == 'existing' && session.expiresAt == DateTime.utc(2026),
        'session refresh preserves token and absolute expiry');
    final device = AddressBookDevice.fromJson({
      'id': 'p',
      'name': 'DC400',
      'tenant_id': 't',
      'remote_id': '1865846518',
      'remote_access_status': 'blocked'
    });
    check(
        device.remoteId == '1865846518' &&
            device.remoteAccessStatus == RemoteTransportStatus.blocked,
        'catalog preserves connection ID and block state');
    final auth = AzsignHttpAuthTransport(http);
    for (final entry in {
      428: TokenPollStatus.pending,
      429: TokenPollStatus.slowDown,
      410: TokenPollStatus.expired,
      403: TokenPollStatus.denied
    }.entries) {
      final poll = await auth.pollToken(
          deviceCode: '${entry.key}', codeVerifier: 'test');
      check(poll.status == entry.value,
          'real auth adapter handles HTTP ${entry.key}');
    }
  } finally {
    http.close();
    await server.close(force: true);
  }
}
