package com.carriez.flutter_hbb;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.Binder;
import android.os.Process;
import android.content.SharedPreferences;

/** ADB-only receipt, never a password/hash export or a remotely writable API. */
public final class AzsignProvisioningProvider extends ContentProvider {
    private static final String PREFS = "azsign-provisioning";
    private static final long TTL = 300000L;

    public static boolean record(Context context, String id, boolean persisted) {
        if (id == null || !id.matches("[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}")) return false;
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .clear().putString("request_id", id)
            .putString("status", persisted ? "persisted" : "failed")
            .putLong("time", System.currentTimeMillis()).commit();
    }

    @Override public boolean onCreate() { return true; }

    @Override public Cursor query(Uri uri, String[] projection, String selection, String[] args, String sort) {
        int uid = Binder.getCallingUid();
        if (uid != 2000 && uid != 0 && uid != Process.myUid()) throw new SecurityException("ADB only");
        if ("/capabilities".equals(uri.getPath())) {
            MatrixCursor cursor = new MatrixCursor(new String[]{"protocol"});
            cursor.addRow(new Object[]{1});
            return cursor;
        }
        if (uri.getPathSegments().size() != 2 || !"password".equals(uri.getPathSegments().get(0))) {
            throw new IllegalArgumentException("Unsupported query");
        }
        String id = uri.getLastPathSegment();
        if (id == null || !id.matches("[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}")) {
            throw new IllegalArgumentException("Invalid request");
        }
        SharedPreferences prefs = getContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        long age = System.currentTimeMillis() - prefs.getLong("time", 0);
        String status = id.equals(prefs.getString("request_id", "")) && age >= 0 && age < TTL
            ? prefs.getString("status", "pending") : "pending";
        MatrixCursor cursor = new MatrixCursor(new String[]{"protocol", "request_id", "status"});
        cursor.addRow(new Object[]{1, id, status});
        return cursor;
    }

    @Override public String getType(Uri uri) { return "vnd.android.cursor.item/azsign-provisioning"; }
    @Override public Uri insert(Uri uri, ContentValues values) { throw new SecurityException("Read only"); }
    @Override public int delete(Uri uri, String selection, String[] args) { throw new SecurityException("Read only"); }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] args) { throw new SecurityException("Read only"); }
}
