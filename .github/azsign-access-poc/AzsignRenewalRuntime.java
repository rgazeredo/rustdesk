package com.carriez.flutter_hbb;

import java.io.File;
import java.nio.charset.StandardCharsets;
import org.json.JSONObject;

/** One scheduler per app process. No network or signing runs on Android's main thread. */
public final class AzsignRenewalRuntime {
    private static AzsignRenewalScheduler scheduler;
    private static String startupFailure = "";

    /** Non-secret diagnostics; no certificate, key, token or signed proof. */
    public static synchronized JSONObject status(File filesDirectory) throws Exception {
        JSONObject result = new JSONObject();
        result.put("state", scheduler == null ? "NOT_STARTED" : scheduler.getState().name());
        result.put("startup_error", startupFailure);
        if (scheduler != null) {
            result.put("next_check_at", scheduler.getNextScheduledAttemptMs());
            result.put("failures", scheduler.getConsecutiveFailures());
            result.put("last_error", scheduler.getLastFailure());
            result.put("transport_authorized", scheduler.isRemoteTransportAuthorized());
        }
        File activeFile = new File(filesDirectory, "azsign-access-poc/active.json");
        result.put("enrolled", activeFile.isFile());
        if (activeFile.isFile()) {
            JSONObject active = new JSONObject(new String(AzsignAccessIdentity.readLimited(activeFile, 32768), StandardCharsets.UTF_8));
            result.put("has_renewal_origin", active.has("renewal_origin"));
            result.put("expires_at", active.optLong("expires_at", 0));
        }
        return result;
    }

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
            startupFailure = "";
        } catch (Exception invalid) {
            startupFailure = invalid.getClass().getSimpleName();
            stop();
        }
    }
}
