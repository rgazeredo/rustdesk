import android.app.UiAutomation;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.os.HandlerThread;
import android.view.View;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityEvent;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;

/** Shell-only temporary diagnostic; no network, credentials, persistent settings or clicks. */
public final class FireAccessibilityProbe {
    private static int nodes, focusable, clickable, clickActions;
    private static AccessibilityNodeInfo settingsCard;
    private static void inspect(AccessibilityNodeInfo node, int depth) {
        if (depth > 48 || ++nodes > 512) return;
        if (node.isVisibleToUser() && node.isEnabled()) {
            if (node.isFocusable()) {
                focusable++;
                android.graphics.Rect b = new android.graphics.Rect(); node.getBoundsInScreen(b);
                if (settingsCard == null && b.width() > 200 && b.height() > 100 && b.contains(600, 350)) settingsCard = AccessibilityNodeInfo.obtain(node);
            }
            if (node.isClickable()) clickable++;
            if ((node.getActions() & AccessibilityNodeInfo.ACTION_CLICK) != 0) clickActions++;
        }
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo child = node.getChild(i);
            if (child == null) continue;
            try { inspect(child, depth + 1); } finally { child.recycle(); }
        }
    }
    public static void main(String[] args) throws Exception {
        HandlerThread thread = new HandlerThread("FireAccessibilityProbe");
        thread.start();
        UiAutomation automation = null;
        try {
            Class<?> connectionType = Class.forName("android.app.IUiAutomationConnection");
            Object connection = Class.forName("android.app.UiAutomationConnection").getDeclaredConstructor().newInstance();
            Constructor<?> constructor = UiAutomation.class.getDeclaredConstructor(android.os.Looper.class, connectionType);
            constructor.setAccessible(true);
            automation = (UiAutomation) constructor.newInstance(thread.getLooper(), connection);
            Method connect = UiAutomation.class.getDeclaredMethod("connect", int.class);
            connect.setAccessible(true);
            connect.invoke(automation, UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES);
            AccessibilityServiceInfo info = automation.getServiceInfo();
            info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED | AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED | AccessibilityEvent.TYPE_VIEW_FOCUSED | AccessibilityEvent.TYPE_WINDOWS_CHANGED;
            info.flags |= AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS | AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS | AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS;
            automation.setServiceInfo(info);
            AccessibilityNodeInfo root = automation.getRootInActiveWindow();
            if (root == null) { System.out.println("probe no_root"); return; }
            try {
                root.refresh(); inspect(root, 0);
                AccessibilityNodeInfo focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);
                AccessibilityNodeInfo target = null;
                try {
                    target = (focused != null ? focused : root).focusSearch(View.FOCUS_RIGHT);
                    System.out.println("probe nodes=" + nodes + " focusable=" + focusable + " clickable=" + clickable + " click_actions=" + clickActions + " focused=" + (focused != null) + " next_focus=" + (target != null));
                    if (args.length == 1 && "test-settings-card".equals(args[0]) && "com.amazon.tv.launcher".contentEquals(root.getPackageName()) && settingsCard != null) {
                        System.out.println("probe card_actions=" + settingsCard.getActions() + " focus_action=" + settingsCard.performAction(AccessibilityNodeInfo.ACTION_FOCUS) + " click_action=" + settingsCard.performAction(AccessibilityNodeInfo.ACTION_CLICK) + " global_center=" + automation.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_DPAD_CENTER));
                    }
                    if (settingsCard != null) settingsCard.recycle();
                } finally {
                    if (target != null && target != root && target != focused) target.recycle();
                    if (focused != null && focused != root) focused.recycle();
                }
            } finally { root.recycle(); }
        } finally {
            if (automation != null) {
                Method disconnect = UiAutomation.class.getDeclaredMethod("disconnect");
                disconnect.setAccessible(true);
                disconnect.invoke(automation);
            }
            thread.quitSafely();
        }
    }
}
