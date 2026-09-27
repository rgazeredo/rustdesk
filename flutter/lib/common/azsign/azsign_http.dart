import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// JSON boundary for the desktop API. No redirects or ambient proxy credentials.
class AzsignHttp {
  final Uri origin;
  final HttpClient _client;
  static const maxResponseBytes = 1024 * 1024;

  AzsignHttp(this.origin, {HttpClient? client})
      : _client = client ?? HttpClient() {
    if (origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      throw ArgumentError('CMS must be an HTTPS origin');
    }
    _client.connectionTimeout = const Duration(seconds: 15);
    _client.findProxy = (_) => 'DIRECT';
  }

  void close() => _client.close(force: true);

  Uri verificationUri(String value) {
    final uri = Uri.parse(value);
    if (uri.origin != origin.origin ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !RegExp(r'^/desktop/authorize/[0-9a-fA-F-]{36}$').hasMatch(uri.path)) {
      throw const FormatException('Invalid browser authorization origin');
    }
    return uri;
  }

  Future<AzsignHttpResponse> request(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (!path.startsWith('/api/v1/desktop/')) {
      throw ArgumentError('Not a desktop endpoint');
    }
    final request = await _client
        .openUrl(method, origin.replace(path: path, queryParameters: query))
        .timeout(const Duration(seconds: 15));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (token != null)
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    try {
      return await (() async {
        final response = await request.close();
        if (response.statusCode >= 300 && response.statusCode < 400) {
          throw const FormatException('CMS redirect refused');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > maxResponseBytes) {
            throw const FormatException('CMS response too large');
          }
          bytes.addAll(chunk);
        }
        if (response.statusCode == 204)
          return AzsignHttpResponse(204, const {});
        if (response.headers.contentType?.mimeType != 'application/json') {
          throw const FormatException('CMS response is not JSON');
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map<String, dynamic>)
          throw const FormatException('Invalid CMS response');
        return AzsignHttpResponse(response.statusCode, decoded);
      })()
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      request.abort();
      rethrow;
    }
  }
}

class AzsignHttpResponse {
  final int status;
  final Map<String, dynamic> data;
  const AzsignHttpResponse(this.status, this.data);
  void requireSuccess() {
    if (status < 200 || status >= 300) throw AzsignApiException(status);
  }
}

class AzsignApiException implements Exception {
  final int status;
  const AzsignApiException(this.status);
  @override
  String toString() => 'CMS request failed ($status)';
}
