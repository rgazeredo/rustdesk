# Non-root D-pad pilot

Adds one hook to InputService's existing main-thread, pre-API-33 key handler.
Arrows use focusSearch/ACTION_FOCUS; Enter/center clicks the focused clickable
node. Editable focus and modified keys preserve the previous text path. Key-up
is consumed to avoid duplicate actions. No root, shell, coordinates, extra
permissions, accessibility-global toggles or automatic clicks while moving focus.

Android 13+ IME path and root/hardware input helpers remain unchanged. This is
accessibility navigation, not physical key injection: launchers with only custom
key listeners may not react. DC400 exposes img_downpage as focusable but not
clickable; whether its focus listener opens the drawer requires a device test.

Apply after existing hardware patches. Build with the dedicated PoC workflow;
do not publish to production. Regression checks: arrow navigation, Enter once,
text/cursor editing, Home/touch, no-focus/disabled/missing target, reconnect and
device/account revocation. Logs contain only key codes and action success.
