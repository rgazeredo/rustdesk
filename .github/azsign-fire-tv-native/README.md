# Native Fire TV input for AZSign Remote

Remote v32 / ARMv7 versionCode 5092, branch `feat/fire-tv-native-remote`.
The backend is restricted to Amazon AFTHY7ABBA / Android 11 API 30. Other models
retain their existing input paths. This is a community-researched protocol,
not an Amazon-supported public SDK. Wire facts were independently implemented
from https://github.com/LibreControl/fire-tv/blob/main/docs/protocol.md.

## Runtime behavior

The APK activates FireTVRemote through DIAL on `127.0.0.1:8009` and uses the
native HTTPS API on `127.0.0.1:8080`. It needs neither an ADB input connection,
a PC helper nor a VPN for control. No input server or extra permission is added.
Normal PIN authorization is mandatory. Never guess PINs or bypass it.

A serialized bounded worker handles network requests. The receiver certificate
is bootstrapped without sending credentials, then pinned exactly before PIN or
token submission. Certificate dates are checked; identity changes fail closed
and require explicitly forgetting and pairing again. The token is encrypted
with AES-GCM using an Android Keystore key in app-private storage. Logs contain
only fixed phase/reason codes and operation outcomes, never PINs, tokens,
exception messages or HTTP bodies. The pairing Activity is not exported.

Before each input, authenticated read-only status is checked. If Fire OS killed
the cached native receiver, DIAL may be reactivated once within bounded recovery.
No key or PIN submission is replayed after an ambiguous response. A release is
attempted even when keyDown fails. Arrows/Enter use native keys. A short mouse
click focuses a bounded visible accessibility node and sends native Select.
Inaccessible nodes, dragging and long presses remain unsupported.

## Configuration and validation

Choose **Configurar controle desta Fire TV**, request the native PIN, read the
four digits and enter them in the Remote configuration. The physical remote
remains paired. During automated QA the native protocol's Back did not dismiss
the PIN window; selecting its Ignore button did, and the displayed PIN was
still accepted by verification. Do not equate native API Back with the physical
remote's Back behavior. The TV reported an amzkeyboard hardware input and its soft keyboard was hidden
during QA; native text entry into the setup field was not confirmed.

On 20 November 2026 the signed v32 APK was installed as an update preserving
UID/device ID. Initial PIN entry used ADB solely for setup, explicitly authorized
by the user; confirmation used native input. The APK encrypted/read back its
credential and reported paired=1, ready=1. The user then confirmed mouse clicks,
arrows and Enter through their normal Remote client. APK logs independently
recorded native selection and completed navigation. The Amazon foreground
service started during diagnosis had been stopped before this client test.
After a full TV reboot, the user confirmed the Remote reconnected and continued
to control clicks, arrows and Enter. The diagnostic VPN/ADB connection had not
returned, independently establishing that runtime control did not depend on it.
Broader models and complete physical-remote-only onboarding remain unvalidated.

Diagnostics found cached receiver exits for LOW_MEMORY. No memory setting,
animation policy or package was changed. A newly issued receiver certificate
replaced its factory certificate; explicit fresh PIN pairing confirmed the
current identity, which survived subsequent DIAL activation. Never silently
replace the saved certificate because a request fails.

## Build and checks

Apply `android/apply.py` after the existing AZSign recovery, D-pad and Fire TV
accessibility patches. It validates every baseline anchor before writing. CI
rebuilds Java/Kotlin/Flutter and signs using existing Actions secrets. The optional
`reuse_native_libraries` verifies both SHA-256 and signer of the published v28
APK and extracts only unchanged Rust/C++ libraries. It requires an unchanged ABI;
v32's Rust library was verified identical to the installed v29 library.

Signed build: https://github.com/rgazeredo/rustdesk/actions/runs/44830132022.
No production catalog or release was published by this task.

    python3 .github/azsign-fire-tv-native/android/test_apply.py
    python3 .github/azsign-fire-tv-native/android/test_transport.py
    python3 -m unittest discover -s .github/azsign-fire-tv-native

Checks cover atomic rejection of upstream drift, real HTTPS certificate pinning,
hardware gates, ordered press/release, release after failed keyDown, redirects,
response limits, invalid headers/paths, PIN rejection and private state storage.
The HTTPS fixture requires Java 17 and local loopback binding.

## Standalone QA probes

These helpers are not part of the Android runtime. Use only on an authorized
receiver, keeping all private state outside the repository (directory 0700,
files 0600). Never commit credentials or customer screenshots.

    python3 .github/azsign-fire-tv-native/probe.py HOST PRIVATE_STATE_DIR activate
    python3 .github/azsign-fire-tv-native/probe.py HOST PRIVATE_STATE_DIR start
    python3 .github/azsign-fire-tv-native/probe.py HOST PRIVATE_STATE_DIR pair
    # pair reads the PIN from stdin, never a command argument.
    python3 .github/azsign-fire-tv-native/probe.py HOST PRIVATE_STATE_DIR status
    python3 .github/azsign-fire-tv-native/short_press.py HOST PRIVATE_STATE_DIR right

`short_press.py` prepares pinned TLS connections before keyDown so a VPN TLS
handshake does not hold a key and cause repeats. It releases in finally and
never automatically retries a key. It exposes only the closed navigation list,
no arbitrary command or power endpoint.
