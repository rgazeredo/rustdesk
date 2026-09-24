# Physical-device regression test

This Android test app compiles **the production `AquarioNodeClick.java`**, without
copying its logic. On a STV-3000 Plus with Android 11 it verifies left click,
scaled stationary touch, ignoring drag/pan/long press/orphan up, disabled targets,
off-screen coordinates, cancellation on close, and modal window isolation.

Build with `sh build.sh`, setting `AZSIGN_ANDROID_SDK` and
`AZSIGN_TEST_KEYSTORE` (an Android debug test key). Install the printed APK on a
test device. Save the original enabled-accessibility-service list, open
`br.com.azsign.gestureprobe/.ProbeActivity`, then append
`br.com.azsign.gestureprobe/br.com.azsign.gestureprobe.ProbeService` to that list.
Keep the diagnostic Activity foreground for 17 seconds. The service skips every
scheduled action if another package becomes active. Read `AZSignProbe` logcat
messages: all 11 assertions must report PASS, without FAIL.

Restore the original accessibility-service list and the previous foreground app.
Remove `br.com.azsign.gestureprobe` when finished. Do not enable this test service
as part of production provisioning. It does not test network input, RustDesk
startup, or reboot recovery; those require the complete pilot APK.

Validated on physical STV-3000 Plus, Android 11, 2026-09-17: 11 PASS / 0 FAIL.
