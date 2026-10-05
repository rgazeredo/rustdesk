package com.carriez.flutter_hbb;

import android.content.Context;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import org.json.JSONObject;

public final class AzsignRecoveryAndroid {
    private static AzsignRecovery recovery;
    private static final String ALIAS = "azsign-remote-managed-password";
    private static native String deviceId();
    private static native boolean applyPassword(String password);
    private static native void restartTransport();

    public static synchronized void start(Context context, String fallbackOrigin) {
        if (recovery != null || android.os.Build.VERSION.SDK_INT < 26) return;
        final Context app = context.getApplicationContext();
        recovery = new AzsignRecovery(new File(app.getFilesDir(), "azsign-access-poc"), new AzsignRecovery.Native() {
            public String deviceId() { return AzsignRecoveryAndroid.deviceId(); }
            public boolean setPassword(String password) {
                if (!applyPassword(password)) return false;
                try { savePassword(app, password); return true; } catch (Exception error) { return false; }
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
    private static SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        if (!store.containsAlias(ALIAS)) {
            KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
            generator.init(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
            return generator.generateKey();
        }
        return (SecretKey) store.getKey(ALIAS, null);
    }
    private static void savePassword(Context context, String password) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key());
        byte[] encrypted = cipher.doFinal(password.getBytes(StandardCharsets.UTF_8));
        boolean saved = context.getSharedPreferences("azsign-managed", Context.MODE_PRIVATE).edit()
            .putString("password", Base64.encodeToString(encrypted, Base64.NO_WRAP))
            .putString("iv", Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP)).commit();
        if (!saved) throw new IllegalStateException("Password storage unavailable");
    }
    public static String revealPassword(Context context) throws Exception {
        android.content.SharedPreferences prefs = context.getSharedPreferences("azsign-managed", Context.MODE_PRIVATE);
        if (!prefs.contains("password")) return "";
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, Base64.decode(prefs.getString("iv", ""), Base64.NO_WRAP)));
        return new String(cipher.doFinal(Base64.decode(prefs.getString("password", ""), Base64.NO_WRAP)), StandardCharsets.UTF_8);
    }
}
