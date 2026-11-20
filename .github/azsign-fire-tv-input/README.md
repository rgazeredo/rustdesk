# Fire TV AFTHY7ABBA input candidate

Branch fix/fire-tv-afthy7abba-input. Scoped to Amazon / AFTHY7ABBA / API 30.
Measured: Remote v29 InputService bound, gestures accepted then cancelled,
D-pad handled=false; shell input and scrcpy keyboard work. These facts do not
prove the event subscription is the sole cause. This is a candidate requiring
physical validation, not a completed compatibility claim.

After Aquario and D-pad patches, apply with Python. Subscribes to window/content
/focus events only on target; refreshes roots and attempts bounded accessibility
node clicks instead of dispatchGesture. No input injection privilege, root,
ADB listener, arbitrary commands, new port, password logging or new remote key.
Long presses/drags are refused; inaccessible nodes remain unsupported. Other
models retain their prior paths. Existing ID/provider and credentials unchanged.

Tests: python3 .github/azsign-fire-tv-input/test.py ; compile FireTvNodeClick.java
against Android SDK. Full APK and actual mouse/keyboard/reboot testing required.
Version reserved: remote.30 / ARMv7 versionCode 5090. Do not publish or install
unsigned APK, debug-signed APK, or APK signed with the player key. The Remote
signer must match becf9e8addbe567faaa67331f1ba0ca080c07e80f640f1ae404b58916cd547dc.
