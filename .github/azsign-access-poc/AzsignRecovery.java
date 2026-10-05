package com.carriez.flutter_hbb;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.cert.*;
import java.util.*;
import java.util.concurrent.*;
import org.json.JSONObject;

/** Independent HTTPS recovery control plane; it never authorizes remote transport itself. */
public final class AzsignRecovery {
    public interface Native {
        String deviceId();
        boolean setPassword(String password);
        void restartTransport();
    }
    interface Transport { JSONObject post(String operation, JSONObject body) throws Exception; }
    private final File dir;
    private final Native nativeApi;
    private final String fallbackOrigin;
    private final ScheduledExecutorService executor = Executors.newSingleThreadScheduledExecutor();
    private volatile String state = "STARTING";
    private volatile String lastError = "";
    private volatile long lastContact;
    private volatile boolean closed;

    public AzsignRecovery(File directory, Native nativeApi, String fallbackOrigin) {
        this.dir = directory; this.nativeApi = nativeApi; this.fallbackOrigin = fallbackOrigin;
    }
    public void start() { executor.scheduleWithFixedDelay(this::tick, 2, 60, TimeUnit.SECONDS); }
    public void close() { closed = true; executor.shutdownNow(); }
    public JSONObject status() throws Exception {
        return new JSONObject().put("state", state).put("last_error", lastError).put("last_contact", lastContact);
    }
    private void tick() {
        if (closed) return;
        try {
            File identityFile = new File(dir, "identity/id");
            if (!identityFile.isFile()) { state = "SETUP_REQUIRED"; return; }
            String id = AzsignAccessIdentity.identityId(new String(AzsignAccessIdentity.readLimited(identityFile, 36), StandardCharsets.US_ASCII));
            JSONObject context = context();
            String origin = AzsignRenewalHttp.validateOrigin(context.optString("renewal_origin", fallbackOrigin));
            AzsignRenewalHttp http = new AzsignRenewalHttp(dir, origin);
            cycle(id, context, http::postRecovery);
        } catch (Exception error) {
            // Exception messages and server bodies may contain credential material.
            lastError = error.getClass().getSimpleName(); state = "RETRYING";
        }
    }
    JSONObject context() throws Exception {
        File active = new File(dir, "active.json");
        File recovery = new File(dir, "recovery.json");
        if (active.isFile()) {
            JSONObject value = read(active);
            // Keep authority/origin independently of the revocable access credential.
            JSONObject minimal = new JSONObject().put("renewal_origin", value.getString("renewal_origin"))
                .put("ca_base64", value.getString("ca_base64"));
            write(recovery, minimal);
            return minimal;
        }
        return recovery.isFile() ? read(recovery) : new JSONObject();
    }
    synchronized void cycle(String id, JSONObject context, Transport http) throws Exception {
        String remoteId = nativeApi.deviceId();
        if (!remoteId.matches("[0-9]{6,16}")) { state = "WAITING_ID"; return; }
        AzsignAccessIdentity identity = new AzsignAccessIdentity(dir);
        byte[] csr = identity.prepare(id);
        File pendingFile = new File(dir, "recovery-pending.json");
        JSONObject pending = pendingFile.isFile() ? read(pendingFile) : null;
        if (pending != null && pending.getLong("expires_at") <= System.currentTimeMillis()) {
            if (!pendingFile.delete()) throw new IOException("Cannot discard expired receipt journal");
            pending = null;
        }
        if (pending == null) {
            JSONObject response = exchange(http, identity, id, remoteId, csr, "prepare", null);
            lastContact = System.currentTimeMillis(); lastError = "";
            if (!"authorized".equals(response.getString("status"))) { state = "WAITING"; return; }
            validate(id, context, response, identity);
            // Password never goes to disk in this journal. On restart obtain it again via proof.
            if (!nativeApi.setPassword(response.getString("password"))) throw new IOException("Password persistence failed");
            JSONObject active = new JSONObject(response.toString());
            active.remove("password"); active.remove("status");
            active.put("renewal_origin", context.optString("renewal_origin", fallbackOrigin));
            pending = active;
            write(pendingFile, pending);
        }
        validate(id, context, pending, identity);
        state = "APPLYING";
        if (closed) return;
        // The certificate is disabled at the gateway until the authenticated receipt.
        AzsignRenewalRuntime.stop();
        write(new File(dir, "active.json"), pending);
        JSONObject receipt = exchange(http, identity, id, remoteId, csr, "confirm", pending.getString("grant_id"));
        lastContact = System.currentTimeMillis();
        if (!"completed".equals(receipt.getString("status"))) {
            new File(dir, "active.json").delete();
            pendingFile.delete();
            state = "WAITING";
            return;
        }
        if (!pendingFile.delete()) throw new IOException("Cannot finish receipt journal");
        AzsignRenewalRuntime.start(dir.getParentFile());
        nativeApi.restartTransport();
        state = "CONFIGURED"; lastError = "";
    }
    private JSONObject exchange(Transport http, AzsignAccessIdentity identity, String id, String remoteId, byte[] csr, String phase, String grant) throws Exception {
        JSONObject challengeResponse = http.post("challenge", new JSONObject().put("identity_id", id));
        String challenge = challengeResponse.getString("challenge");
        if (!challenge.matches("[A-Za-z0-9_-]{43}") || challengeResponse.getInt("expires_in") != 120) throw new SecurityException("Invalid challenge");
        JSONObject body = new JSONObject().put("identity_id", id).put("remote_id", remoteId).put("phase", phase)
            .put("challenge", challenge).put("csr_base64", Base64.getEncoder().encodeToString(csr));
        if (grant != null) body.put("grant_id", grant);
        body.put("proof_base64", identity.signRecovery(id, phase, grant, remoteId, challenge, csr));
        return http.post("exchange", body);
    }
    private void validate(String id, JSONObject context, JSONObject response, AzsignAccessIdentity identity) throws Exception {
        if (!id.equals(response.getString("identity_id"))) throw new SecurityException("Identity mismatch");
        AzsignAccessIdentity.identityId(response.getString("grant_id"));
        byte[] ca = Base64.getDecoder().decode(response.getString("ca_base64"));
        if (context.has("ca_base64") && !MessageDigest.isEqual(ca, Base64.getDecoder().decode(context.getString("ca_base64")))) throw new SecurityException("Authority changed");
        X509Certificate leaf = identity.verifyCertificate(id, Base64.getDecoder().decode(response.getString("certificate_base64")), ca);
        if (response.getLong("expires_at") != leaf.getNotAfter().getTime()) throw new SecurityException("Expiry mismatch");
        JSONObject profile = response.getJSONObject("profile");
        if (profile.length() != 5) throw new SecurityException("Invalid profile");
        for (String field : new String[]{"host", "server_name"}) {
            String host = profile.getString(field);
            if (host.length() > 253 || !host.matches("[a-z0-9]+([.-][a-z0-9]+)*")) throw new SecurityException("Invalid host");
        }
        for (String field : new String[]{"registration", "rendezvous", "relay"}) {
            int port = profile.getInt(field);
            if (port < 1024 || port > 65535) throw new SecurityException("Invalid port");
        }
        if (response.has("password") && !response.getString("password").matches("[A-Za-z0-9]{24}")) throw new SecurityException("Invalid managed password");
    }
    private static JSONObject read(File file) throws Exception {
        return new JSONObject(new String(AzsignAccessIdentity.readLimited(file, 32768), StandardCharsets.UTF_8));
    }
    static void write(File file, JSONObject data) throws Exception {
        File temporary = new File(file.getParentFile(), file.getName()+".new");
        try (FileOutputStream output = new FileOutputStream(temporary)) {
            if (!temporary.setReadable(false, false) || !temporary.setWritable(false, false)
                || !temporary.setReadable(true, true) || !temporary.setWritable(true, true)) throw new IOException("Private storage unavailable");
            output.write(data.toString().getBytes(StandardCharsets.UTF_8)); output.getFD().sync();
        }
        if (!temporary.renameTo(file)) throw new IOException("Atomic recovery persist failed");
    }
}
