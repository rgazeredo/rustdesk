# SmartPro accessibility recovery

PROSB3000 Android 10 firmware's DisplayContent.updateFocusedWindowLocked clears all accessibility services on every non-Netflix focus change. Both native gestures and node clicks work while input is bound. Confirmed on physical hardware, including a real reboot and user-confirmed remote RustDesk clicks on 2026-09-17.

The universal APK restores the RustDesk component using a ContentObserver while its sharing service is active. Provision once with `pm grant com.carriez.flutter_hbb android.permission.WRITE_SECURE_SETTINGS`. Permission is the opt-in; no ADB, root, companion APK or external computer is used at runtime. Existing services are preserved. Other models and Android versions are inert.

Recovery coalesces writes for 100 ms and backs off after 12 repairs per 10 seconds. It stops with the sharing service or manual input stop; manual stop persists across reboot. Opening accessibility through RustDesk enables recovery again. Android settings alone cannot be distinguished from the firmware's deletion; use RustDesk's input switch to disable it, or revoke the provisioned permission.

The original standalone hardware probe restored after BOOT_COMPLETED at about 71 seconds. The integrated release must still be tested independently, including screen capture after reboot. A brief input gap can occur during the Android service rebind.
