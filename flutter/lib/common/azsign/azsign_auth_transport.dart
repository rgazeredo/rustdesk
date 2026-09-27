import 'azsign_types.dart';

class AzsignAuthorizationRequest {
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;
  const AzsignAuthorizationRequest(
      {required this.deviceCode,
      required this.userCode,
      required this.verificationUri,
      required this.expiresIn,
      this.interval = 3});
}

enum TokenPollStatus { pending, slowDown, expired, denied, approved }

class AzsignTokenPollResult {
  final TokenPollStatus status;
  final AzsignSession? session;
  final String? errorMessage;
  const AzsignTokenPollResult(
      {required this.status, this.session, this.errorMessage});
}

abstract class AzsignAuthTransport {
  Future<AzsignAuthorizationRequest> requestAuthorization(
      {required String codeChallenge,
      required String deviceId,
      required String deviceLabel,
      String? clientVersion});
  Future<AzsignTokenPollResult> pollToken(
      {required String deviceCode, required String codeVerifier});
  Future<AzsignSession?> fetchSession(String token);
  Future<void> revokeSession(String token);
}
