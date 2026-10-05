# Client integration status — 2026-09-26

Branch `fix/azsign-client-integration`, based on Gemini's `073b6594c`.
## Desktop integration checkpoint — branch feat/azsign-desktop-native

Work in progress, not published. The original desktop right pane is preserved
unless a macOS build explicitly defines AZSIGN_DESKTOP_CMS_ORIGIN. The pilot
pane uses real HTTPS browser authorization and catalog adapters, absolute token
expiry, and a native macOS login-Keychain implementation (no plaintext fallback).
Connect now invokes the real CMS enrollment/profile/certificate endpoints, native
CSR creation and certificate installation before applying gateway options and
opening the existing RustDesk connection flow. A native feature probe refuses
ordinary builds without the mTLS socket layer. Existing proxy is untouched.

Verified: 15 previous Dart HTTPS checks against a disposable TLS server; 7 Flutter
tests including issuance/logout cancellation and native-feature enforcement;
native Swift CSR signature/PKCS8 checked by OpenSSL, certificate chain/clientAuth,
CN and key matching checked by Security.framework; macOS hbb_common cargo check
and expiry/inactive/invalid identity unit test passed. Keychain operations inside
the packaged app and a real gateway session have NOT been validated.

The upstream lockfile needed 16 dependency reconciliations with the workflow's
Flutter 3.24.5 (mostly SDK-pinned test packages). It is now resolved and passes
pub get --enforce-lockfile. Bridge generation 1.80.1 succeeded. The isolated test
harness retains its own lockfile. Native libraries were compiled with the pinned
vcpkg revision. Full macOS arm64 release packaging completed successfully:
`flutter/build/macos/Build/Products/Release/AZSignRemotePilot.app` (55.9 MB).
Ad-hoc codesign deep/strict verification passed; bundle identifier is
`com.azsign.remote.pilot`, URL scheme is `azsign-rustdesk-pilot`. The packaged
library exports both native capability and local session-logout entry points.
The packaged executable's `--version` smoke invocation exited successfully
(without version output). Focused Flutter analysis reports no issues.
This is build validation, not live Keychain/CMS/gateway homologation.

CMS companion worktree rustdesk-desktop-cms now binds each desktop operator
identity to its login session. Registry certificate lookup (used by policy and
session permits) rejects expired/logged-out desktop sessions; legacy Setup
identities retain their existing path. Enrollment/profile/certificate endpoints
are feature-gated and not deployed. Native RSA-2048 generation, CN-only CSR,
certificate validation and atomic Keychain record installation are implemented.
The Rust macOS loader reads that record, never laboratory files/environment, and
rejects expired/inactive credentials. Keychain reads run off the Tokio executor.
Final connection/logout end-to-end remains unfinished.

Regression surface: desktop_home_page adds one macOS opt-in branch; the original
path remains unchanged. MainFlutterWindow adds only Keychain IPC methods and
Xcode includes their helpers. Gemini's AZSign-only auth/types now support real API
responses and honest network/logout failure handling. The feature-gated macOS
core uses AZSignRemotePilot configuration; build-only product/bundle/URL-scheme
settings keep stock RustDesk separate. macOS transport reads Keychain; Android
credential behavior is unchanged. apply.mjs is repeatable and accepts --desktop
to avoid generating Android build files. No DC400 or production deployment occurred.

Build entry point: `.github/azsign-access-poc/build-desktop-macos.sh`, run from
the fork root with the documented tools on PATH and VCPKG_ROOT configured. It
creates a local ad-hoc pilot, not a notarized distributable or installation.

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
# Windows desktop port — 2026-09-27

Branch `feat/azsign-desktop-windows` isolates a snapshot of the working native
macOS pilot. Windows enrollment uses RSA-2048/CSR in Rust and user-bound DPAPI
records in LocalAppData/AZSignRemotePilot/SecureStore. No plaintext or laboratory
credential fallback. TLS uses that same record. Logout deletes enrollment and
closes local sessions; the CMS/gateway remains the authority for remote permits.

Local verification: 7 Flutter regression tests and 15 assertions through real
HTTPS sockets passed; the changed native-channel Dart files analyze cleanly.
Windows DPAPI/CSR/certificate tests and the full executable build run in
`azsign-windows-pilot.yml`; compilation is not a claim of interactive Windows
homologation. The portable ZIP is unsigned. Production, gateway and Android
were not changed for this port.


## 2026-10-05 — domínio duplo e catálogo após recuperação (1.5.3)

Diagnóstico no DC400xx: Android v25 registrado no hbbs como 1293024870, captura
e MainService ativos, política do gateway habilitada. Catálogo macOS aberto
continuava conectando ao ID antigo 1865846518. O link atualizado do CMS usava
o ID correto, mas o Android anunciava remote.azsign.com.br:21117; o desktop
com perfil rustdesk.azsign.com.br recusava esse destino lógico. Gateway recebia
apenas a ponta Android e fechava com pairing_timeout. Manter apenas o anúncio
do hbbs no domínio antigo não foi suficiente: o cliente também informa relay.

Correções restritas ao desktop autenticado: módulo de aliases do Android
reutilizado, aceitando apenas o par exato de nomes AZSign quando host e SNI
provisionados pertencem ao par. Socket, SNI, CA, certificado, portas e controles
de sessão continuam derivados do perfil autenticado. Outros hosts/IP/loopback
continuam recusados. Nenhum default ou perfil persistido no CMS foi alterado.

Conectar pela lista recarrega a página atual do catálogo e resolve pelo UUID
do player e tenant antes de provisionar/conectar. ID remoto não é reaproveitado
se o cadastro desapareceu, mudou de empresa, perdeu o vínculo, foi bloqueado
ou se o CMS falhou. Links do painel mantêm o fluxo existente.

Superfície de regressão: azsign_access.rs altera validação do destino lógico
TCP/UDP somente dentro da feature azsign-access-poc; apply.mjs copia o módulo
novo para a build; azsign_desktop_page.dart revalida cliques do catálogo;
pubspec.yaml identifica 1.5.3+71. Nenhuma assinatura compartilhada nem caminho
sem a feature foi alterado. O submódulo já continha patches de transporte;
nenhum bump de commit foi feito.

Verificação: 17 testes Flutter (incluindo recuperação, destino removido e falha
do CMS) e dois testes Rust de aliases aprovados. Build macOS e validação física
ainda em andamento ao registrar esta seção; não confundir testes com conexão
gráfica homologada.

Build macOS ARM64 1.5.3+71 finalizada: biblioteca Rust e app Flutter compilados,
assinatura ad hoc deep/strict e DMG verificados. Instalado em
`/Applications/AZSign Remote.app`, mesmo bundle ID com.azsign.remote.pilot e
protocolo azsign-remote. Backup do aplicativo 1.5.2 em
`azsign/output/artifacts/remote-1.5.3/previous-1.5.2/AZSign Remote.app`.
Pacote e hashes em `azsign/output/artifacts/remote-1.5.3/verification.json`.
Nenhum login ou conexão remota iniciado pelo agente. Solicitado ao usuário
abrir o aplicativo e testar o DC400xx; sessão gráfica ainda não confirmada.
