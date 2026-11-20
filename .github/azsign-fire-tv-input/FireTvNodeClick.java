package com.carriez.flutter_hbb;

import android.accessibilityservice.AccessibilityService;
import android.content.res.Configuration;
import android.graphics.Rect;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.ViewConfiguration;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** Scoped accessibility input for the measured Amazon Fire TV model. */
public final class FireTvNodeClick {
    private static final String TAG = "AZSignFireNodeClick";
    private final AccessibilityService service;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final int slop;
    private boolean down, moved;
    private int startX, startY;
    private long startedAt;

    public FireTvNodeClick(AccessibilityService service) {
        this.service = service;
        slop = ViewConfiguration.get(service).getScaledTouchSlop();
    }

    public static boolean isTarget() {
        return Build.VERSION.SDK_INT == 30
            && "Amazon".equalsIgnoreCase(Build.MANUFACTURER)
            && "AFTHY7ABBA".equalsIgnoreCase(Build.MODEL);
    }

    private boolean enabled() {
        return isTarget();
    }

    // RustDesk button packets use the cursor from the latest move, not their x/y fields.
    public synchronized boolean mouse(int mask, int x, int y) {
        if (!enabled()) return false;
        switch (mask) {
            case 9: begin(x, y); return true;
            case 0:
            case 8: move(x, y); return true;
            case 10: end(x, y); return true;
            case 523331: FireTvNativeRemote.get(service).press("dpad_down"); return true;
            case 963: FireTvNativeRemote.get(service).press("dpad_up"); return true;
            default: return false;
        }
    }

    public synchronized boolean touch(int mask, int x, int y, int scale) {
        if (!enabled()) return false;
        switch (mask) {
            case 4: begin(Math.max(0, x) * scale, Math.max(0, y) * scale); return true;
            // Pan updates are deltas; any pan must not accidentally activate a button.
            case 5: if (down && (x != 0 || y != 0)) moved = true; return true;
            case 6: end(startX, startY); return true;
            default: return false;
        }
    }

    private void begin(int x, int y) {
        down = true;
        moved = false;
        startX = x;
        startY = y;
        startedAt = SystemClock.uptimeMillis();
    }

    private void move(int x, int y) {
        if (down && (Math.abs(x - startX) > slop || Math.abs(y - startY) > slop)) moved = true;
    }

    private void end(int x, int y) {
        if (!down) return;
        move(x, y);
        down = false;
        if (moved || SystemClock.uptimeMillis() - startedAt > ViewConfiguration.getLongPressTimeout()) {
            Log.i(TAG, "unsupported drag or long press; no click sent");
            return;
        }
        final int clickX = startX, clickY = startY;
        main.post(() -> click(clickX, clickY));
    }

    public synchronized void close() {
        down = false;
        main.removeCallbacksAndMessages(null);
        FireTvNativeRemote.cancelInput(service);
    }

    private void click(int x, int y) {
        List<AccessibilityWindowInfo> windows = new ArrayList<>(service.getWindows());
        windows.sort(Comparator.comparingInt(AccessibilityWindowInfo::getLayer).reversed());
        AccessibilityNodeInfo root = null;
        try {
            Rect bounds = new Rect();
            for (AccessibilityWindowInfo window : windows) {
                window.getBoundsInScreen(bounds);
                if (bounds.contains(x, y)) {
                    root = window.getRoot();
                    // Never click through a top window whose nodes are unavailable.
                    if (root == null) { Log.i(TAG, "no accessible root at cursor"); return; }
                    break;
                }
            }
            if (windows.isEmpty()) root = service.getRootInActiveWindow();
            if (root == null) { Log.i(TAG, "no window at cursor"); return; }
            if (!root.refresh()) { Log.i(TAG, "stale accessibility root; click refused"); return; }
            AccessibilityNodeInfo target = findTarget(root, x, y, 0, new int[] {512});
            if (target == null) { Log.i(TAG, "no accessible click target"); return; }
            try {
                boolean focused = target.isFocused() || target.performAction(AccessibilityNodeInfo.ACTION_FOCUS);
                if (focused) {
                    main.postDelayed(() -> FireTvNativeRemote.get(service).press("select"), 50);
                    Log.i(TAG, "Native selection queued");
                } else if (target.isClickable()) {
                    Log.i(TAG, "Node click result=" + target.performAction(AccessibilityNodeInfo.ACTION_CLICK));
                } else Log.i(TAG, "Focus refused; no selection sent");
            } finally { target.recycle(); }
        } catch (RuntimeException e) {
            Log.w(TAG, "node click failed: " + e.getClass().getSimpleName());
        } finally {
            if (root != null) root.recycle();
            for (AccessibilityWindowInfo window : windows) window.recycle();
        }
    }

    private AccessibilityNodeInfo findTarget(AccessibilityNodeInfo node, int x, int y, int depth, int[] budget) {
        if (depth > 64 || --budget[0] < 0 || !node.isVisibleToUser() || !node.isEnabled()) return null;
        Rect bounds = new Rect();
        node.getBoundsInScreen(bounds);
        if (!bounds.contains(x, y)) return null;
        for (int i = node.getChildCount() - 1; i >= 0; i--) {
            AccessibilityNodeInfo child = node.getChild(i);
            if (child == null) continue;
            try {
                child.getBoundsInScreen(bounds);
                if (!child.isVisibleToUser() || !bounds.contains(x, y)) continue;
                if (!child.isEnabled()) { budget[0] = -1; return null; }
                AccessibilityNodeInfo target = findTarget(child, x, y, depth + 1, budget);
                if (target != null) return target;
                // Only consider this branch or its clickable ancestor, never an overlapping sibling.
                break;
            } finally { child.recycle(); }
        }
        return budget[0] >= 0 && (node.isFocusable() || node.isClickable() || (node.getActions() & AccessibilityNodeInfo.ACTION_CLICK) != 0) ? AccessibilityNodeInfo.obtain(node) : null;
    }
}
