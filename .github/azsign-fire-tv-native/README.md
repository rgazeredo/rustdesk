# Native Fire TV input for AZSign Remote

Branch: feat/fire-tv-native-remote. Remote v32 integration candidate, scoped to
Amazon AFTHY7ABBA / API 30. Normal PIN authorization is required. Never guess
PINs, retry pairing automatically, or bypass authorization.

Protocol facts were independently implemented from:
https://github.com/LibreControl/fire-tv/blob/main/docs/protocol.md
This is a community-researched interface, not an Amazon-supported public SDK.

Observed on the user-authorized Amazon AFTHY7ABBA/Android 11 on 20 November 2026:
DIAL port 8009 exposed FireTVRemote in stopped state. POST activation returned
201. Native port 8080 became reachable. TLS succeeded with the receiver
certificate fixed in private local state. PIN display returned description OK.
PIN pairing succeeded. A fresh client process reused the saved credential and
passed authenticated status without requesting a new PIN. Native Home, Back,
left/right/down and Enter moved focus and opened the Settings screen; the screen
was visually verified and MainSettingsActivity was observed. No input keyevent
was sent through ADB. ADB was used to read/capture the screen and restore the
player afterwards. Player normal BACK 3x exit was sent through the native protocol
to avoid kiosk focus recovery masking the test. No TV preference changed.
On-device loopback activation and HTTPS reachability were verified independently.
Full TV reboot, mouse-to-node mapping and the integrated signed APK still require
physical validation. Remote v29/v30 do not contain this backend.
Do not confuse endpoint availability with functional input or boot persistence.

Usage (state must be outside this repository):

    python3 .github/azsign-fire-tv-native/probe.py HOST PRIVATE_STATE_DIR activate
    python3 .github/azsign-fire-tv-native/probe.py HOST PRIVATE_STATE_DIR start
    python3 .github/azsign-fire-tv-native/probe.py HOST PRIVATE_STATE_DIR pair
    # pair reads the one-time PIN from stdin; never pass it in command arguments.
    python3 .github/azsign-fire-tv-native/probe.py HOST PRIVATE_STATE_DIR status
    python3 .github/azsign-fire-tv-native/probe.py HOST PRIVATE_STATE_DIR right

The first public receiver certificate is bootstrapped over the authorized VPN
endpoint without sending a credential. Requests then require certificate
validation and an exact leaf pin before sending PIN/token. No automatic trust
reset, TLS downgrade, credential/body logging, ADB command, root, account login,
or firmware/configuration changes. State directory mode 0700; files 0600.
Commands are bounded to eight seconds and 64 KiB response size. Only explicit
navigation keys are exposed, not arbitrary endpoint URLs or power actions.

Unit checks: python3 -m unittest discover -s .github/azsign-fire-tv-native
Four tests cover PIN rejection, private persistence/no token output, paired
ordered down/up events and fail-closed certificate changes before HTTP output.
Physical input must still be tested after the user supplies the PIN.

## Android integration

Apply `android/apply.py` after the recovery, D-pad and Fire TV accessibility
patches. It fails before writing if baseline anchors diverge. Maintained Java
sources are copied into the generated upstream build tree by CI.

On the Remote home page choose **Configurar controle desta Fire TV**. Request a
PIN, read the native dialog, dismiss it with the physical Back button and enter
the four digits. Dismissing the dialog before verifying was tested successfully.
The non-exported configuration Activity accepts no token or PIN through intents.
The encrypted token is stored in private preferences using Android Keystore
AES-GCM. Its certificate remains pinned; identity changes require explicitly
forgetting and pairing again. No input server, ADB dependency, off-device helper
or additional permission is introduced. Only DIAL HTTP on loopback is permitted;
the authenticated native API uses HTTPS on loopback.

Arrows/Enter go to the native backend. Mouse clicks focus a bounded, visible
accessibility node then send native Select. Unavailable nodes, long presses and
drags remain unsupported. Other hardware keeps its existing input path.

`android/test_transport.py` runs a real JVM HTTPS fixture covering hardware
gating, ordered presses, pinned TLS, redirects, response bounds and rejected
headers/paths. It needs Java 17 and permission to bind local loopback.
The workflow's optional `reuse_native_libraries` verifies both SHA-256 and signer
of the published v28 APK and extracts only unchanged Rust/C++ libraries. Kotlin,
Java and Flutter are rebuilt and signed in Actions; signing secrets never leave
CI. This option requires unchanged Rust ABI. Version: remote.32 / ARMv7 code5092.

Remote v31 was built, signature-verified and installed preserving the existing
UID/device ID. The integrated pairing UI opened and requested a PIN locally,
but a later initialization failed with SocketException while the native service
was not listening. v32 extends only bounded, read-only initialization retries
from ConnectException to SocketException and logs fixed phase/reason codes. TLS
identity errors still fail closed and input/PIN submission is never retried.
The TV also replaced its factory receiver certificate with a newly issued
Amazon subordinate certificate; a fresh PIN pairing confirmed that identity.
That newer certificate and probe credential survived a DIAL service restart.
Integrated pairing, actual Remote input and full reboot remain pending.

ApplicationExitInfo subsequently confirmed native receiver exits for LOW_MEMORY
while cached (importance 400). v32 checks authenticated status before each input,
reactivates DIAL at most once per bounded read-only recovery and validates status
again before sending a key. No key or PIN request is replayed. The pairing
bootstrap likewise retries read-only discovery and verifies any stored pin
before issuing a new PIN display. No memory policy or package was changed.
