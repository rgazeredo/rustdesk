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

/** Aquário Android 11 rejects dispatchGesture on its NOTOUCH display. */
public final class AquarioNodeClick {
    private static final String TAG = "AZSignNodeClick";
    private final AccessibilityService service;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final int slop;
    private boolean down, moved;
    private int startX, startY;
    private long startedAt;

    public AquarioNodeClick(AccessibilityService service) {
        this.service = service;
        slop = ViewConfiguration.get(service).getScaledTouchSlop();
    }

    private boolean enabled() {
        return Build.VERSION.SDK_INT == 30
            && "Aquario".equalsIgnoreCase(Build.MANUFACTURER)
            && "STV3000Plus".equalsIgnoreCase(Build.MODEL.replaceAll("[^A-Za-z0-9]", ""))
            && service.getResources().getConfiguration().touchscreen == Configuration.TOUCHSCREEN_NOTOUCH;
    }

    // RustDesk button packets use the cursor from the latest move, not their x/y fields.
    public synchronized boolean mouse(int mask, int x, int y) {
        if (!enabled()) return false;
        switch (mask) {
            case 9: begin(x, y); return true;
            case 0:
            case 8: move(x, y); return true;
            case 10: end(x, y); return true;
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
            AccessibilityNodeInfo target = findTarget(root, x, y, 0, new int[] {512});
            if (target == null) { Log.i(TAG, "no accessible click target"); return; }
            try {
                boolean result = target.performAction(AccessibilityNodeInfo.ACTION_CLICK);
                Log.i(TAG, "ACTION_CLICK result=" + result);
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
        return budget[0] >= 0 && node.isClickable() ? AccessibilityNodeInfo.obtain(node) : null;
    }
}
