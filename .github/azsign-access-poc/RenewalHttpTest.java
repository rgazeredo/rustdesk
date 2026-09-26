package com.carriez.flutter_hbb;

import java.io.*;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.cert.Certificate;
import javax.net.ssl.HttpsURLConnection;
import org.json.JSONObject;

/** Executes the real HTTP adapter, replacing only the connection boundary. */
public final class RenewalHttpTest {
    interface Check { void run() throws Exception; }
    static void rejects(Class<? extends Throwable> type, Check check) throws Exception {
        try { check.run(); } catch (Exception failure) {
            if (type.isInstance(failure)) return;
            throw failure;
        }
        throw new AssertionError("Expected " + type.getName());
    }
    static final class Connection extends HttpsURLConnection {
        int code = 200;
        String json = "{\"challenge\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\",\"expires_in\":120}";
        String type = "application/json; charset=utf-8";
        boolean disconnected;
        ByteArrayOutputStream request = new ByteArrayOutputStream();
        Connection(URL url) { super(url); }
        public void disconnect() { disconnected = true; }
        public boolean usingProxy() { return false; }
        public void connect() {}
        public String getCipherSuite() { return "TLS_AES_128_GCM_SHA256"; }
        public Certificate[] getLocalCertificates() { return null; }
        public Certificate[] getServerCertificates() { return new Certificate[0]; }
        public OutputStream getOutputStream() { return request; }
        public int getResponseCode() { return code; }
        public String getContentType() { return type; }
        public InputStream getInputStream() { return new ByteArrayInputStream(json.getBytes(StandardCharsets.UTF_8)); }
        public InputStream getErrorStream() { return getInputStream(); }
    }
    public static void main(String[] args) throws Exception {
        File directory = new File(args[0]);
        String id = args[1];
        for (String invalid : new String[]{"http://cms.test", "https://user@cms.test", "https://cms.test/path", "https://cms.test?token=x", "https://cms.test#x", "https://cms.test:8443", "https://cms.test\\@evil.test"}) {
            rejects(Exception.class, () -> AzsignRenewalHttp.validateOrigin(invalid));
        }
        Connection[] last = new Connection[1];
        AzsignRenewalHttp transport = new AzsignRenewalHttp(directory, "https://cms.test/", url -> last[0] = new Connection(url));
        transport.requestChallenge(id);
        Connection request = last[0];
        if (!request.getURL().toString().equals("https://cms.test/api/v1/rustdesk-access/device-renewal/challenge")
            || request.getInstanceFollowRedirects() || request.getReadTimeout() != 10000
            || !request.disconnected) throw new AssertionError("Unsafe connection options");
        JSONObject body = new JSONObject(request.request.toString("UTF-8"));
        if (!body.getString("certificate_fingerprint").matches("[A-F0-9]{2}(:[A-F0-9]{2}){31}") || body.length() != 2) throw new AssertionError("Invalid challenge request");
        JSONObject active = new JSONObject(new String(java.nio.file.Files.readAllBytes(new File(directory, "active.json").toPath()), StandardCharsets.UTF_8));
        byte[] certificate = java.util.Base64.getDecoder().decode(active.getString("certificate_base64"));
        long expiry = ((java.security.cert.X509Certificate) java.security.cert.CertificateFactory.getInstance("X.509")
            .generateCertificate(new ByteArrayInputStream(certificate))).getNotAfter().getTime();
        active.put("expires_at", expiry);
        AzsignRenewalHttp success = new AzsignRenewalHttp(directory, "https://cms.test", url -> {
            Connection c = new Connection(url); c.json = active.toString(); last[0] = c; return c;
        });
        if (!java.util.Arrays.equals(certificate, success.submitRenewal(id, new byte[]{1}, "nonce", "proof").certificate)) throw new AssertionError("Invalid decoded certificate");
        JSONObject submission = new JSONObject(last[0].request.toString("UTF-8"));
        if (submission.length() != 4 || !submission.getString("proof_base64").equals("proof") || !submission.getString("csr_base64").equals("AQ==")) throw new AssertionError("Invalid renewal request");
        active.put("expires_at", expiry + 1);
        rejects(SecurityException.class, () -> success.submitRenewal(id, new byte[]{1}, "nonce", "proof"));
        active.put("expires_at", expiry).put("identity_id", "another-identity");
        rejects(SecurityException.class, () -> success.submitRenewal(id, new byte[]{1}, "nonce", "proof"));
        for (int status : new int[]{301,302,307,308,401,404,409,429,500,503}) {
            AzsignRenewalHttp failing = new AzsignRenewalHttp(directory, "https://cms.test", url -> {
                Connection c = new Connection(url); c.code = status; c.json = "{\"code\":\"identity_revoked\"}"; return c;
            });
            rejects(IOException.class, () -> failing.submitRenewal(id, new byte[]{1}, "nonce", "proof"));
        }
        for (String code : new String[]{"identity_revoked", "reenrollment_required", "temporarily_blocked"}) {
            int status = code.equals("temporarily_blocked") ? 423 : 403;
            AzsignRenewalHttp failing = new AzsignRenewalHttp(directory, "https://cms.test", url -> {
                Connection c = new Connection(url); c.code = status; c.json = new JSONObject().put("code", code).toString(); return c;
            });
            Class<? extends Throwable> type = code.equals("identity_revoked") ? AzsignRenewalScheduler.RevokedException.class
                : code.equals("reenrollment_required") ? AzsignRenewalScheduler.ReenrollmentException.class : AzsignRenewalScheduler.BlockedException.class;
            rejects(type, () -> failing.submitRenewal(id, new byte[]{1}, "nonce", "proof"));
            if (status == 403) rejects(IOException.class, () -> failing.requestChallenge(id));
        }
        for (String bad : new String[]{"x", "{}", new String(new char[33000]).replace('\0', 'x')}) {
            AzsignRenewalHttp malformed = new AzsignRenewalHttp(directory, "https://cms.test", url -> {
                Connection c = new Connection(url); c.json = bad; return c;
            });
            rejects(Exception.class, () -> malformed.requestChallenge(id));
        }
        AzsignRenewalHttp cancelled = new AzsignRenewalHttp(directory, "https://cms.test", url -> { throw new AssertionError("No request after cancellation"); });
        cancelled.cancel();
        rejects(InterruptedIOException.class, () -> cancelled.requestChallenge(id));
        System.out.println("http-verified");
    }
}
