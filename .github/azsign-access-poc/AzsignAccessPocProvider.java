package com.carriez.flutter_hbb;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Binder;
import android.os.ParcelFileDescriptor;
import java.io.File;
import java.io.FileNotFoundException;

/** Lab build only: shell-only write channel. Never exports credentials. */
public final class AzsignAccessPocProvider extends ContentProvider {
    @Override public boolean onCreate() { return true; }
    @Override public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        int uid = Binder.getCallingUid();
        if (uid != 2000 && uid != 0) throw new SecurityException("ADB only");
        if (!"w".equals(mode)) throw new SecurityException("Write only");
        String name = uri.getLastPathSegment();
        if (uri.getPathSegments().size() != 1 || name == null ||
            !(name.equals("profile.json") || name.equals("ca.der") || name.equals("device.der") || name.equals("device.key.der"))) {
            throw new FileNotFoundException("Unsupported file");
        }
        File dir = new File(getContext().getFilesDir(), "azsign-access-poc");
        if (!dir.isDirectory() && !dir.mkdir()) throw new FileNotFoundException("Cannot create private profile");
        return ParcelFileDescriptor.open(new File(dir, name),
            ParcelFileDescriptor.MODE_WRITE_ONLY | ParcelFileDescriptor.MODE_CREATE | ParcelFileDescriptor.MODE_TRUNCATE);
    }
    @Override public String getType(Uri uri) { return "application/octet-stream"; }
    @Override public Cursor query(Uri u, String[] p, String s, String[] a, String o) { throw new SecurityException("No export"); }
    @Override public Uri insert(Uri u, ContentValues v) { throw new SecurityException("Unsupported"); }
    @Override public int update(Uri u, ContentValues v, String s, String[] a) { throw new SecurityException("Unsupported"); }
    @Override public int delete(Uri u, String s, String[] a) { throw new SecurityException("Unsupported"); }
}
