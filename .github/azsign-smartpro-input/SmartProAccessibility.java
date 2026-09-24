package com.carriez.flutter_hbb;

import android.Manifest;
import android.content.ComponentName;
import android.content.Context;
import android.content.pm.PackageManager;
import android.database.ContentObserver;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.Settings;
import android.util.Log;
import java.util.ArrayDeque;
import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.Set;

/** Restores input after the SmartPro WindowManager clears accessibility on focus changes. */
public final class SmartProAccessibility {
    private static final String TAG = "AZSignSmartPro";
    private static final String KEY = Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES;
    private static final String PREFS = "azsign-smartpro-input";
    private static final String TARGET = "com.carriez.flutter_hbb/com.carriez.flutter_hbb.InputService";
    private static SmartProAccessibility instance;
    private final Context context;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final ArrayDeque<Long> attempts = new ArrayDeque<>();
    private final Runnable repair = this::repair;
    private boolean closed;
    private final ContentObserver observer = new ContentObserver(handler) {
        @Override public void onChange(boolean selfChange) {
            // Coalesce the two firmware writes without delaying forever during frequent events.
            if (!closed && !handler.hasCallbacks(repair)) handler.postDelayed(repair, 100);
        }
    };

    private SmartProAccessibility(Context context) { this.context = context.getApplicationContext(); }

    private static boolean supported(Context context) {
        return Build.VERSION.SDK_INT == 29
            && Build.MODEL.toUpperCase(Locale.ROOT).contains("PROSB3000")
            && context.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED;
    }

    public static void start(Context context) {
        if (instance != null || !supported(context)
                || context.getSharedPreferences(PREFS, 0).getBoolean("manually-disabled", false)) return;
        SmartProAccessibility keeper = new SmartProAccessibility(context);
        instance = keeper;
        context.getContentResolver().registerContentObserver(Settings.Secure.getUriFor(KEY), false, keeper.observer);
        context.getContentResolver().registerContentObserver(
            Settings.Secure.getUriFor(Settings.Secure.ACCESSIBILITY_ENABLED), false, keeper.observer);
        keeper.repair();
    }

    public static void stop() {
        if (instance == null) return;
        SmartProAccessibility keeper = instance;
        instance = null;
        keeper.closed = true;
        keeper.handler.removeCallbacksAndMessages(null);
        keeper.context.getContentResolver().unregisterContentObserver(keeper.observer);
    }

    public static void setManuallyDisabled(Context context, boolean disabled) {
        if (!supported(context)) return;
        context.getSharedPreferences(PREFS, 0).edit().putBoolean("manually-disabled", disabled).apply();
        if (disabled) stop();
    }

    private void repair() {
        if (closed) return;
        try {
            String raw = Settings.Secure.getString(context.getContentResolver(), KEY);
            Set<String> services = new LinkedHashSet<>();
            boolean present = false;
            ComponentName target = ComponentName.unflattenFromString(TARGET);
            if (raw != null) for (String item : raw.split(":")) {
                if (item.isEmpty()) continue;
                services.add(item);
                if (target.equals(ComponentName.unflattenFromString(item))) present = true;
            }
            boolean enabled = Settings.Secure.getInt(context.getContentResolver(), Settings.Secure.ACCESSIBILITY_ENABLED, 0) == 1;
            if (present && enabled) return;
            long now = SystemClock.uptimeMillis();
            while (!attempts.isEmpty() && now - attempts.peekFirst() >= 10000) attempts.removeFirst();
            if (attempts.size() >= 12) {
                handler.removeCallbacks(repair);
                handler.postDelayed(repair, Math.max(100, 10000 - (now - attempts.peekFirst())));
                Log.w(TAG, "Frequent resets; recovery backing off");
                return;
            }
            attempts.addLast(now);
            if (!present) {
                services.add(TARGET);
                if (!Settings.Secure.putString(context.getContentResolver(), KEY, String.join(":", services))) {
                    Log.e(TAG, "Accessibility write rejected"); stop(); return;
                }
            }
            if (!enabled && !Settings.Secure.putInt(context.getContentResolver(), Settings.Secure.ACCESSIBILITY_ENABLED, 1)) {
                Log.e(TAG, "Accessibility enable rejected"); stop(); return;
            }
            Log.i(TAG, "Input restored at uptime=" + now);
        } catch (RuntimeException error) {
            Log.e(TAG, "Recovery stopped", error);
            stop();
        }
    }
}
