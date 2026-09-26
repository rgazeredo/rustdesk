# Client integration status — 2026-09-26

Branch `fix/azsign-client-integration`, based on Gemini's `073b6594c`.
## Physical DC400 validation — 2026-09-26

APK v19 installed on DC400. Initial enrollment failed because Conscrypt returns
OpenSSLRSAPrivateKey, which does not implement RSAPrivateCrtKey. Reproduced with
the actual release classes on Android and a failing JVM non-CRT regression test.
The loader now reconstructs the public component from the existing local PKCS#8
encoding, retaining native JCA signing and the same private key. Identity tests,
provider compilation and renewal suites pass with BC 1.86. A diagnostic DEX
running as the app UID on the DC400 successfully generated the CSR with the fix;
this is not yet validation of the complete corrected APK. v20 build required.
Production identity: 01a0df4a-8aab-714b-9aa3-dc56d0a12c77, bound to the existing
DC400 player. No private key exported. Reboot/renewal/block-release end-to-end
tests remain pending. Earlier local-only notes below are historical.

## Security corrections implemented

- Renewal signs a fresh challenge and SHA-256 of CSR DER using the enrolled RSA
  key. Canonical message is UTF-8 with LF separators and no final LF:
  `AZSIGN-RUSTDESK-RENEWAL-V1`, identity UUID, challenge, lowercase CSR hash.
  The CMS still needs to implement verification and single-use challenge storage;
  a client signature alone does not prevent replay at the server.
- Renewal cannot silently replace the enrolled CA or gateway profile and must
  extend the existing certificate validity. Additional enrollment metadata is
  preserved rather than discarded.
- Temporary blocking uses a different exception from permanent revocation,
  retains enrollment and retries. The gateway remains the enforcement authority;
  a locally valid certificate does not mean a session is authorized.
- Removed generic unauthenticated TCP loopback bypass, including `0.0.0.0`.
  Existing IPC uses `parity_tokio_ipc`. Remote TCP always uses the enrolled gateway
  and TLS. Full native transport build/device regression is still required.
- Java tests execute the real identity/scheduler implementations, including
  signature verification, different nonce, profile/CA substitution, certificate
  replay, temporary block, permanent revocation and expired certificate.

## Android integration added (local, not deployed)

- Real HTTPS challenge/renew adapter with platform web PKI, no redirects, bounded
  responses, timeouts, fingerprint binding and cancellation. Remote enrollment CA
  is not installed as web trust. Revocation is only accepted after proof submission.
- One scheduler per process, started by the patched MainApplication and restarted
  after provider activation. Existing RustDesk boot receiver/service behavior and
  its permissions are preserved. Automatic boot still requires that setup enabled
  the existing start-on-boot option and Android allows the app to start.
- Stops do not wait on network responses; a late response cannot overwrite a newer
  enrollment. Private atomic writes preserve renewal metadata and local key.
- Setup branch `fix/setup-renewal-origin` passes the connected CMS origin, never
  its bearer token. New capability `renewal_protocol=1` prevents silent enrollment
  with an older APK. Existing enrollments without an origin need one Setup update.
- JVM tests cover the production HTTP adapter through a fake connection boundary,
  runtime restart from disk, cancellation, real CSR/proof/certificates, blocks,
  revocation and expiry. Provider and helpers compile against Android API 34.
- Setup: 401 tests and Node/Web typechecks passed in Docker.

## Not finished / not safe to publish as complete

- CMS renewal endpoints from Claude integrated locally in AZSign branch
  `feat/rustdesk-gateway-lifecycle` (merge `0254e319`): 164 focused CMS tests,
  683 assertions passed, including a real Java-generated signature vector.
  Still no live HTTPS client-to-CMS or physical-device homologation.
- Android accepts an exactly identical, valid certificate as an idempotent CMS
  response without rewriting enrollment. A different non-extending certificate
  remains rejected; unchanged responses wait at least 60 seconds before retry.
- Pre-publication reviews remain: exact CN-only subject for original enrollment,
  production-mode renewal tests, and trusted proxy/rate-limit deployment behavior.
- Android device reboot/offline integration tests against the real CMS and a
  complete native APK build (JVM/API compilation is not an APK build).
- Desktop native secure storage, real HTTP adapters, operator key/certificate
  enrollment and binding the Flutter screens to the production application.
- CMS browser authorization and scoped Address Book endpoints, including client
  visibility limits. Do not equate tenant membership to access to all players.
- Actual Dart/Flutter tests and builds (the inherited JavaScript desktop test
  only tests its own simulation).
- End-to-end DC400 pilot: connect, block, reject reconnect, unblock, reconnect,
  verify session console history, and certificate renewal without ADB.

Local Java verification uses supplied BC jars (currently 1.79) and OpenSSL 3;
the APK pipeline pins BC 1.86 and still requires its own build validation.
