# Aquário node-click pilot

The STV-3000 Plus Android 11 firmware rejects accessibility gestures because its
display configuration reports `TOUCHSCREEN_NOTOUCH`. A physical-device probe
confirmed that `ACTION_CLICK` still activates accessible buttons.

`apply.py` adds thin hooks to RustDesk 1.4.9's `InputService`. The existing cursor
scaling and move-before-button protocol remain authoritative. The helper handles
left click and stationary touch through `ACTION_CLICK` only on Aquario / STV-3000
Plus / Android 11 / NOTOUCH. Other devices and non-left mouse buttons keep their
existing paths. Drags and long presses are consumed without activating buttons.
The top accessible window and deepest hit branch are used to avoid clicking
through dialogs; node traversal is bounded and node handles are recycled.

This pilot has application ID `com.carriez.flutter_hbb.aquariopilot` so installing
it does not erase the existing RustDesk app. Sign downloaded builds with the same
local pilot key for subsequent updates. Production app data is not shared.

No shell helper, root, network listener, boot-time ADB command or new Android
permission is introduced. Startup uses the existing RustDesk boot and accessibility
services. A real reboot and remote-input test are still required before acceptance.

Build changes are applied after the existing provisioning and MCD-125 patches in
`azsign-android.yml`. Never install the APK as a universal fleet replacement:
accessible-node clicks do not provide arbitrary-coordinate gestures.
