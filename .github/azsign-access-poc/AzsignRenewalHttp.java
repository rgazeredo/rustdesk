package com.carriez.flutter_hbb;

import java.io.*;
import java.net.URI;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.util.Base64;
import java.util.Locale;
import javax.net.ssl.HttpsURLConnection;
import org.json.JSONObject;

/** Uses Android's normal web PKI. Never installs a trust-all verifier or follows redirects. */
public final class AzsignRenewalHttp implements AzsignRenewalScheduler.RenewalTransport {
    interface Connections { HttpsURLConnection open(URL url) throws IOException; }
    private final File directory;
    private final String origin;
    private final Connections connections;
    private volatile HttpsURLConnection current;
    private volatile boolean cancelled;
    private static final String PATH = "/api/v1/rustdesk-access/device-renewal/";

    public AzsignRenewalHttp(File directory, String origin) throws Exception {
        this(directory, origin, url -> (HttpsURLConnection) url.openConnection());
    }

    AzsignRenewalHttp(File directory, String origin, Connections connections) throws Exception {
        this.directory = directory;
        this.origin = validateOrigin(origin);
        this.connections = connections;
    }

    public static String validateOrigin(String value) throws Exception {
        if (value == null || value.length() > 300) throw new SecurityException("Invalid CMS origin");
        URI uri = new URI(value);
        if (!"https".equals(uri.getScheme()) || uri.getHost() == null
            || !uri.getHost().matches("[a-z0-9]+([.-][a-z0-9]+)*")
            || uri.getUserInfo() != null || uri.getRawQuery() != null || uri.getRawFragment() != null
            || !(uri.getRawPath().isEmpty() || "/".equals(uri.getRawPath()))
            || (uri.getPort() != -1 && uri.getPort() != 443)) {
            throw new SecurityException("CMS must be an HTTPS origin on port 443");
        }
        return "https://" + uri.getHost();
    }

    @Override public synchronized void cancel() {
        cancelled = true;
        if (current != null) current.disconnect();
    }

    @Override public String requestChallenge(String identityId) throws Exception {
        JSONObject active = new JSONObject(new String(AzsignAccessIdentity.readLimited(new File(directory, "active.json"), 32768), StandardCharsets.UTF_8));
        if (!identityId.equals(active.getString("identity_id"))) throw new SecurityException("Identity changed");
        byte[] cert = Base64.getDecoder().decode(active.getString("certificate_base64"));
        StringBuilder fingerprint = new StringBuilder();
        for (byte b : MessageDigest.getInstance("SHA-256").digest(cert)) {
            if (fingerprint.length() > 0) fingerprint.append(':');
            fingerprint.append(String.format(Locale.ROOT, "%02X", b & 255));
        }
        JSONObject request = new JSONObject().put("identity_id", identityId).put("certificate_fingerprint", fingerprint.toString());
        JSONObject response = post("challenge", request, false);
        String challenge = response.getString("challenge");
        if (!challenge.matches("[A-Za-z0-9_-]{43}") || response.getInt("expires_in") != 120) {
            throw new IOException("Invalid renewal challenge response");
        }
        return challenge;
    }

    @Override public AzsignRenewalScheduler.RenewalPayload submitRenewal(String id, byte[] csr, String challenge, String proof) throws Exception {
        JSONObject response = post("renew", new JSONObject().put("identity_id", id).put("challenge", challenge)
            .put("csr_base64", Base64.getEncoder().encodeToString(csr)).put("proof_base64", proof), true);
        if (!id.equals(response.getString("identity_id"))) throw new SecurityException("Response identity mismatch");
        byte[] cert = decode(response.getString("certificate_base64"));
        byte[] ca = decode(response.getString("ca_base64"));
        X509Certificate leaf = (X509Certificate) CertificateFactory.getInstance("X.509")
            .generateCertificate(new ByteArrayInputStream(cert));
        if (response.getLong("expires_at") != leaf.getNotAfter().getTime()) throw new SecurityException("Certificate expiry mismatch");
        return new AzsignRenewalScheduler.RenewalPayload(cert, ca, response.getJSONObject("profile"));
    }

    private static byte[] decode(String value) throws IOException {
        if (value.length() > 12000 || !value.matches("[A-Za-z0-9+/]+={0,2}")) throw new IOException("Invalid certificate encoding");
        byte[] bytes = Base64.getDecoder().decode(value);
        if (bytes.length > 8192) throw new IOException("Oversized certificate");
        return bytes;
    }

    private JSONObject post(String operation, JSONObject body, boolean authenticatedProof) throws Exception {
        HttpsURLConnection connection;
        synchronized (this) {
            if (cancelled) throw new InterruptedIOException("Renewal cancelled");
            connection = connections.open(new URL(origin + PATH + operation));
            current = connection;
        }
        try {
            connection.setInstanceFollowRedirects(false);
            connection.setConnectTimeout(10000);
            connection.setReadTimeout(10000);
            connection.setUseCaches(false);
            connection.setRequestMethod("POST");
            connection.setDoOutput(true);
            connection.setRequestProperty("Content-Type", "application/json");
            connection.setRequestProperty("Accept", "application/json");
            byte[] bytes = body.toString().getBytes(StandardCharsets.UTF_8);
            if (bytes.length > 32768) throw new IOException("Oversized renewal request");
            connection.setFixedLengthStreamingMode(bytes.length);
            try (OutputStream output = connection.getOutputStream()) { output.write(bytes); }
            int status = connection.getResponseCode();
            // A redirect must never forward the signed proof to another origin.
            if (status >= 300 && status < 400) throw new IOException("CMS redirect refused");
            String contentType = connection.getContentType();
            if (contentType == null || !contentType.toLowerCase(Locale.ROOT).split(";", 2)[0].trim().equals("application/json")) {
                throw new IOException("CMS did not return JSON");
            }
            InputStream stream = status == 200 ? connection.getInputStream() : connection.getErrorStream();
            if (stream == null) throw new IOException("Empty CMS response");
            JSONObject response;
            try (InputStream input = stream; ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[1024];
                int count;
                while ((count = input.read(buffer)) != -1) {
                    if (output.size() + count > 32768) throw new IOException("Oversized CMS response");
                    output.write(buffer, 0, count);
                }
                response = new JSONObject(new String(output.toByteArray(), StandardCharsets.UTF_8));
            }
            if (cancelled) throw new InterruptedIOException("Renewal cancelled");
            String code = response.optString("code");
            // Destructive conclusions are only accepted after submitting a signed proof.
            if (authenticatedProof && status == 403 && "identity_revoked".equals(code)) throw new AzsignRenewalScheduler.RevokedException("Identity revoked");
            if (authenticatedProof && status == 403 && "reenrollment_required".equals(code)) throw new AzsignRenewalScheduler.ReenrollmentException("Enrollment required");
            if (status == 423 && "temporarily_blocked".equals(code)) throw new AzsignRenewalScheduler.BlockedException("Temporarily blocked");
            if (status != 200) throw new IOException("CMS renewal unavailable (HTTP " + status + ")");
            return response;
        } finally {
            connection.disconnect();
            synchronized (this) { if (current == connection) current = null; }
        }
    }
}
