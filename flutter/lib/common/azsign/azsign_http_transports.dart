import 'azsign_http.dart';
import 'azsign_types.dart';
import 'azsign_auth_transport.dart';
import 'azsign_address_book_adapter.dart';

class AzsignHttpAuthTransport implements AzsignAuthTransport {
  final AzsignHttp http;
  AzsignHttpAuthTransport(this.http);

  @override
  Future<AzsignAuthorizationRequest> requestAuthorization(
      {required String codeChallenge,
      required String deviceId,
      required String deviceLabel,
      String? clientVersion}) async {
    final response =
        await http.request('POST', '/api/v1/desktop/authorizations', body: {
      'code_challenge': codeChallenge,
      'device_id': deviceId,
      'device_label': deviceLabel,
      if (clientVersion != null) 'client_version': clientVersion,
    });
    response.requireSuccess();
    final data = response.data;
    return AzsignAuthorizationRequest(
        deviceCode: data['device_code'] as String,
        userCode: data['user_code'] as String,
        verificationUri:
            http.verificationUri(data['verification_uri'] as String).toString(),
        expiresIn: data['expires_in'] as int,
        interval: data['interval'] as int);
  }

  @override
  Future<AzsignTokenPollResult> pollToken(
      {required String deviceCode, required String codeVerifier}) async {
    final response = await http
        .request('POST', '/api/v1/desktop/authorizations/token', body: {
      'device_code': deviceCode,
      'code_verifier': codeVerifier,
    });
    switch (response.status) {
      case 428:
        return const AzsignTokenPollResult(status: TokenPollStatus.pending);
      case 429:
        return const AzsignTokenPollResult(status: TokenPollStatus.slowDown);
      case 410:
        return const AzsignTokenPollResult(status: TokenPollStatus.expired);
      case 403:
        return const AzsignTokenPollResult(status: TokenPollStatus.denied);
      default:
        response.requireSuccess();
    }
    return AzsignTokenPollResult(
        status: TokenPollStatus.approved,
        session: AzsignSession.fromJson(response.data));
  }

  @override
  Future<AzsignSession?> fetchSession(String token) async {
    final response =
        await http.request('GET', '/api/v1/desktop/session', token: token);
    if ([401, 403, 404].contains(response.status)) return null;
    response.requireSuccess();
    return AzsignSession.fromJson(response.data, existingToken: token);
  }

  @override
  Future<void> revokeSession(String token) async {
    final response =
        await http.request('DELETE', '/api/v1/desktop/session', token: token);
    if (response.status != 401) response.requireSuccess();
  }
}

class AzsignHttpAddressBookTransport implements AzsignAddressBookTransport {
  final AzsignHttp http;
  AzsignHttpAddressBookTransport(this.http);

  @override
  Future<AzsignAddressBookResponse> fetchCatalog(
      {required String token,
      int page = 1,
      int perPage = 20,
      AzsignAddressBookFilter? filter}) async {
    // The current CMS contract does not implement this filter. Never silently ignore it.
    if (filter?.remoteAccessStatus != null)
      throw UnsupportedError('Remote status filter unavailable');
    final response = await http.request('GET', '/api/v1/desktop/address-book',
        token: token,
        query: {
          'page': '$page',
          'per_page': '$perPage',
          ...?filter?.toQueryParameters()
        });
    response.requireSuccess();
    return AzsignAddressBookResponse.fromJson(response.data);
  }
}
