# MCD-125 root input pilot v5

Opt-in experimental alternative to AccessibilityService for the MCD-125 firmware
that clears enabled_accessibility_services in DisplayContent.enableNfxAccessibility.
No firmware edits, root installation, network listener, exported component or shell
command interface. The existing authenticated RustDesk session forwards numeric
input events to a private app_process child over stdin/stdout.

Activation requires model MCD-125/MCD_125 and an explicit private file:
`/data/user/0/com.carriez.flutter_hbb/files/azsign-root-input-enabled`.
Create the empty marker with existing authorized root access; restart RustDesk.
Remove the marker and restart RustDesk to disable the pilot.
Unsupported devices or absence of the marker retain the existing accessibility path.

The helper is extracted from the installed APK classpath, not downloaded at runtime.
The Java entry point must be kept by R8. Root availability alone is not proof of
input injection: the helper acknowledges every accepted command and disables the
root path if input is rejected. No typed text or full commands are logged.

Supported pilot: mouse click and drag, touch pan, Home (middle click), Back,
Recents (long middle click), wheel and mapped keys. No Unicode/IME composition,
multi-touch/pinch or right-click long-press yet. Idle held input is canceled after
2 seconds; long holds beyond this are not supported. The queue is bounded and
overload disables the helper. EOF releases held input. Keyboard permission still
comes from RustDesk session authentication and the existing native permission path.

Runtime surface: InputService publishes availability; MainService starts/stops
the helper and routes authenticated input; MainActivity stops the helper when
input is explicitly disabled. Existing accessibility code is otherwise unchanged.
No Box Manager or production APK URL changes.

Bench evidence: standalone helper compiled with javac + D8 and launched on SDK29
MCD_125. Motion DOWN/UP and DOWN/MOVE/MOVE/UP acknowledged and visible in dumpsys
input. APK integration, remote client and reboot acceptance remain to be tested.
