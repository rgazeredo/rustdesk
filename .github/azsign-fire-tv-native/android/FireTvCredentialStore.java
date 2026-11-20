package com.carriez.flutter_hbb;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import java.security.KeyStore;
import java.security.GeneralSecurityException;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** App-private encrypted token; Android Keystore key survives same-signer updates. */
final class FireTvCredentialStore {
    private static final String ALIAS = "azsign.firetv.native.v1";
    private final SharedPreferences prefs;
    FireTvCredentialStore(Context context) { prefs = context.getSharedPreferences("azsign-firetv-native", Context.MODE_PRIVATE); }
    private SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        if (!store.containsAlias(ALIAS)) {
            KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
            generator.init(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).build());
            generator.generateKey();
        }
        return (SecretKey) store.getKey(ALIAS, null);
    }
    byte[] certificate() { String value = prefs.getString("certificate", ""); return value.isEmpty() ? null : Base64.decode(value, Base64.NO_WRAP); }
    String token() throws Exception {
        String encrypted = prefs.getString("token", ""); if (encrypted.isEmpty()) return null;
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, Base64.decode(prefs.getString("iv", ""), Base64.NO_WRAP)));
        return new String(cipher.doFinal(Base64.decode(encrypted, Base64.NO_WRAP)), java.nio.charset.StandardCharsets.UTF_8);
    }
    void save(byte[] certificate, String token) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key());
        byte[] encrypted = cipher.doFinal(token.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        if (!prefs.edit().putString("certificate", Base64.encodeToString(certificate, Base64.NO_WRAP))
            .putString("iv", Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP))
            .putString("token", Base64.encodeToString(encrypted, Base64.NO_WRAP)).commit()) throw new GeneralSecurityException("Credential persistence failed");
    }
    void invalidateToken() { prefs.edit().remove("token").remove("iv").commit(); }
    void clear() throws GeneralSecurityException { if (!prefs.edit().clear().commit()) throw new GeneralSecurityException("Credential reset failed"); }
}
