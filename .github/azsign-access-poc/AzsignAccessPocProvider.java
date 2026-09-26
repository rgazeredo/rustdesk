package com.carriez.flutter_hbb;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Binder;
import android.os.ParcelFileDescriptor;
import android.os.Bundle;
import android.util.AtomicFile;
import android.util.Base64;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileNotFoundException;
import java.nio.charset.StandardCharsets;
import org.json.JSONObject;

/** Pilot enrollment. Shell/root only; no private key import/export. */
public final class AzsignAccessPocProvider extends ContentProvider {
    @Override public boolean onCreate() { return true; }
    @Override public synchronized Bundle call(String method, String arg, Bundle extras) {
        int uid = Binder.getCallingUid();
        if (uid != 2000 && uid != 0) throw new SecurityException("ADB only");
        try {
            String id = AzsignAccessIdentity.identityId(arg);
            File dir = new File(getContext().getFilesDir(), "azsign-access-poc");
            AzsignAccessIdentity identity = new AzsignAccessIdentity(dir);
            Bundle result = new Bundle();
            result.putInt("protocol", 2);
            result.putString("identity_id", id);
            if ("prepare-identity".equals(method)) {
                result.putString("csr_base64", Base64.encodeToString(identity.prepare(id), Base64.NO_WRAP));
            } else if ("activate".equals(method)) {
                if (extras == null) throw new IllegalArgumentException("Enrollment required");
                byte[] ca = decode(extras.getString("ca_base64"), 8192);
                byte[] cert = decode(extras.getString("certificate_base64"), 8192);
                java.security.cert.X509Certificate leaf = identity.verifyCertificate(id, cert, ca);
                JSONObject profile = new JSONObject(new String(decode(extras.getString("profile_base64"), 2048), StandardCharsets.UTF_8));
                if (profile.length() != 5) throw new IllegalArgumentException("Invalid profile");
                for (String field : new String[]{"host", "server_name"}) {
                    String host = profile.getString(field);
                    if (host.length() > 253 || !host.matches("[a-z0-9]+([.-][a-z0-9]+)*")) throw new IllegalArgumentException("Invalid gateway host");
                }
                for (String field : new String[]{"registration", "rendezvous", "relay"}) {
                    Object port = profile.get(field);
                    if (!(port instanceof Integer) || (Integer) port < 1024 || (Integer) port > 65535) throw new IllegalArgumentException("Invalid port");
                }
                JSONObject active = new JSONObject();
                active.put("identity_id", id);
                active.put("profile", profile);
                active.put("certificate_base64", Base64.encodeToString(cert, Base64.NO_WRAP));
                active.put("ca_base64", Base64.encodeToString(ca, Base64.NO_WRAP));
                active.put("expires_at", leaf.getNotAfter().getTime());
                AtomicFile file = new AtomicFile(new File(dir, "active.json"));
                FileOutputStream stream = null;
                try {
                    stream = file.startWrite();
                    stream.write(active.toString().getBytes(StandardCharsets.UTF_8));
                    file.finishWrite(stream);
                } catch (Exception error) {
                    if (stream != null) file.failWrite(stream);
                    throw error;
                }
                result.putString("status", "activated");
            } else throw new IllegalArgumentException("Unsupported enrollment operation");
            return result;
        } catch (Exception error) {
            throw new IllegalStateException("Enrollment refused; check identity, certificate and profile");
        }
    }
    private static byte[] decode(String value, int maximum) {
        if (value == null || value.length() > maximum * 2 || !value.matches("[A-Za-z0-9+/]+={0,2}")) throw new IllegalArgumentException("Invalid encoding");
        byte[] decoded = Base64.decode(value, Base64.NO_WRAP);
        if (decoded.length > maximum) throw new IllegalArgumentException("Oversized enrollment");
        return decoded;
    }
    @Override public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException { throw new SecurityException("File import/export disabled"); }
    @Override public String getType(Uri uri) { return "application/octet-stream"; }
    @Override public Cursor query(Uri u, String[] p, String s, String[] a, String o) { throw new SecurityException("No export"); }
    @Override public Uri insert(Uri u, ContentValues v) { throw new SecurityException("Unsupported"); }
    @Override public int update(Uri u, ContentValues v, String s, String[] a) { throw new SecurityException("Unsupported"); }
    @Override public int delete(Uri u, String s, String[] a) { throw new SecurityException("Unsupported"); }
}
