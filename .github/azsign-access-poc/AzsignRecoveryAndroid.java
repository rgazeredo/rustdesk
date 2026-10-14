package com.carriez.flutter_hbb;

import android.content.Context;
import java.io.File;
import java.nio.charset.StandardCharsets;
import org.json.JSONObject;

public final class AzsignRecoveryAndroid {
    private static AzsignRecovery recovery;
    private static native String deviceId();
    private static native boolean applyPassword(String password);
    private static native void restartTransport();

    public static synchronized void start(Context context, String fallbackOrigin) {
        if (recovery != null || android.os.Build.VERSION.SDK_INT < 26) return;
        final Context app = context.getApplicationContext();
        app.getSharedPreferences("azsign-managed", Context.MODE_PRIVATE).edit().clear().apply();
        recovery = new AzsignRecovery(new File(app.getFilesDir(), "azsign-access-poc"), new AzsignRecovery.Native() {
            public String deviceId() { return AzsignRecoveryAndroid.deviceId(); }
            public boolean setPassword(String password) {
                return applyPassword(password);
            }
            public void restartTransport() { AzsignRecoveryAndroid.restartTransport(); }
        }, fallbackOrigin);
        recovery.start();
    }
    public static synchronized String status(Context context) throws Exception {
        JSONObject value = recovery == null ? new JSONObject().put("state", "SETUP_REQUIRED") : recovery.status();
        value.put("renewal", AzsignRenewalRuntime.status(context.getFilesDir()));
        File active = new File(context.getFilesDir(), "azsign-access-poc/active.json");
        if (active.isFile()) {
            JSONObject data = new JSONObject(new String(AzsignAccessIdentity.readLimited(active, 32768), StandardCharsets.UTF_8));
            value.put("profile", data.getJSONObject("profile"));
            value.put("player_name", data.optString("player_name"));
            value.put("tenant_name", data.optString("tenant_name"));
        }
        return value.toString();
    }
}
