# Client integration status — 2026-09-26

Branch `fix/azsign-client-integration`, based on Gemini's `073b6594c`.
No production deployment or APK installation performed.

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

## Not finished / not safe to publish as complete

- CMS renewal challenge/issuance endpoints and one-time replay protection.
- Android HTTPS renewal transport, initialization after enrollment/on startup,
  cancellation/reload behavior and device restart/offline integration tests.
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
