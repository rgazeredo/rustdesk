package com.carriez.flutter_hbb;

import java.io.File;
import java.nio.charset.StandardCharsets;
import org.json.JSONObject;

/** One scheduler per app process. No network or signing runs on Android's main thread. */
public final class AzsignRenewalRuntime {
    private static AzsignRenewalScheduler scheduler;

    public static synchronized void stop() {
        if (scheduler != null) scheduler.close();
        scheduler = null;
    }

    public static synchronized void start(File filesDirectory) {
        if (scheduler != null) return;
        File directory = new File(filesDirectory, "azsign-access-poc");
        File activeFile = new File(directory, "active.json");
        if (!activeFile.isFile()) return;
        try {
            JSONObject active = new JSONObject(new String(AzsignAccessIdentity.readLimited(activeFile, 32768), StandardCharsets.UTF_8));
            // Old enrollments require a one-time Setup update. Never guess the CMS URL
            // from the gateway hostname or embed a production installation here.
            String origin = active.getString("renewal_origin");
            scheduler = new AzsignRenewalScheduler(directory, new AzsignRenewalHttp(directory, origin));
            scheduler.start();
        } catch (Exception invalid) {
            stop();
        }
    }
}
