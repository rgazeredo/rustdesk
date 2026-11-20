# Native Fire TV protocol validation

Branch: investigate/fire-tv-native-pairing. Probe only, not integrated into the
Remote APK or homologated product support. This uses no ADB and requests normal
PIN authorization. Never guess PINs, retry pairing automatically, or bypass it.

Protocol facts were independently implemented from:
https://github.com/LibreControl/fire-tv/blob/main/docs/protocol.md
This is a community-researched interface, not an Amazon-supported public SDK.

Observed on the user-authorized Amazon AFTHY7ABBA/Android 11 on 20 November 2026:
DIAL port 8009 exposed FireTVRemote in stopped state. POST activation returned
201. Native port 8080 became reachable. TLS succeeded with the receiver
certificate fixed in private local state. PIN display returned description OK.
Waiting for the physical TV PIN; pairing, keys and reconnect remain unverified.
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
