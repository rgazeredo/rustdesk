package com.carriez.flutter_hbb;

import android.accessibilityservice.AccessibilityService;
import android.util.Log;
import android.view.KeyEvent;
import android.view.View;
import android.view.accessibility.AccessibilityNodeInfo;

/** Non-root navigation for the pre-Android-13 accessibility input path. */
public final class AzsignDpadNavigation {
    private AzsignDpadNavigation() {}

    public static boolean handle(AccessibilityService service, KeyEvent event) {
        final int key = event.getKeyCode();
        final int direction;
        switch (key) {
            case KeyEvent.KEYCODE_DPAD_UP: direction = View.FOCUS_UP; break;
            case KeyEvent.KEYCODE_DPAD_DOWN: direction = View.FOCUS_DOWN; break;
            case KeyEvent.KEYCODE_DPAD_LEFT: direction = View.FOCUS_LEFT; break;
            case KeyEvent.KEYCODE_DPAD_RIGHT: direction = View.FOCUS_RIGHT; break;
            case KeyEvent.KEYCODE_ENTER:
            case KeyEvent.KEYCODE_NUMPAD_ENTER:
            case KeyEvent.KEYCODE_DPAD_CENTER: direction = 0; break;
            default: return false;
        }
        if (event.isAltPressed() || event.isCtrlPressed() || event.isMetaPressed()
                || event.isShiftPressed()) return false;
        AccessibilityNodeInfo root = service.getRootInActiveWindow();
        if (root == null) return false;
        AccessibilityNodeInfo focused = null;
        AccessibilityNodeInfo target = null;
        try {
            focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);
            // Cursor movement, text selection and Enter in editors keep the old path.
            if (focused != null && focused.isEditable()) return false;
            if (event.getAction() != KeyEvent.ACTION_DOWN) return true;
            boolean success = false;
            if (direction != 0) {
                target = (focused != null ? focused : root).focusSearch(direction);
                if (target != null && target.isVisibleToUser() && target.isEnabled()
                        && target.getWindowId() == root.getWindowId()) {
                    success = target.performAction(AccessibilityNodeInfo.ACTION_FOCUS);
                }
            } else if (focused != null && focused.isVisibleToUser() && focused.isEnabled()
                    && focused.isClickable()) {
                success = focused.performAction(AccessibilityNodeInfo.ACTION_CLICK);
            }
            // No text, labels, coordinates or application data in diagnostics.
            Log.i("AZSignDpad", "key=" + key + " handled=" + success);
            // Never feed navigation into the legacy synthetic text editor.
            return true;
        } finally {
            if (target != null && target != focused && target != root) target.recycle();
            if (focused != null && focused != root) focused.recycle();
            root.recycle();
        }
    }
}
