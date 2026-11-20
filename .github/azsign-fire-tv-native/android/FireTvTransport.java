package com.carriez.flutter_hbb;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSession;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;

/** Loopback-only transport. Never exposes an input server or contacts a remote host. */
public final class FireTvTransport {
    public static final class HttpFailure extends IOException {
        public final int status;
        HttpFailure(int status) { super("Fire TV HTTP " + status); this.status = status; }
    }
    private final String host;
    private final int port;
    private final byte[] certificate;

    public FireTvTransport(byte[] certificate) { this("127.0.0.1", 8080, certificate); }

    // Fixture constructor remains package-private and loopback-only.
    FireTvTransport(String host, int port, byte[] certificate) {
        if (!"127.0.0.1".equals(host) && !"::1".equals(host)) throw new IllegalArgumentException("Loopback required");
        if (certificate == null || certificate.length == 0 || certificate.length > 16384) throw new IllegalArgumentException("Certificate required");
        this.host = host; this.port = port; this.certificate = certificate.clone();
    }

    public static void activate() throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL("http://127.0.0.1:8009/apps/FireTVRemote").openConnection();
        try {
            connection.setConnectTimeout(2000); connection.setReadTimeout(3000);
            connection.setInstanceFollowRedirects(false); connection.setUseCaches(false);
            connection.setRequestMethod("POST"); connection.setDoOutput(true);
            connection.setFixedLengthStreamingMode(0);
            connection.getOutputStream().close();
            if (connection.getResponseCode() != 201) throw new IOException("Fire TV activation refused");
        } finally { connection.disconnect(); }
    }

    /** Public-certificate discovery only. No application data or credentials sent. */
    public static byte[] discoverCertificate() throws IOException, GeneralSecurityException {
        return discoverCertificate("127.0.0.1", 8080);
    }

    static byte[] discoverCertificate(String host, int port) throws IOException, GeneralSecurityException {
        if (!"127.0.0.1".equals(host) && !"::1".equals(host)) throw new IllegalArgumentException("Loopback required");
        final X509Certificate[] observed = new X509Certificate[1];
        SSLContext context = SSLContext.getInstance("TLS");
        context.init(null, new TrustManager[]{new X509TrustManager() {
            public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
            public void checkClientTrusted(X509Certificate[] chain, String auth) throws CertificateException { throw new CertificateException("Not a server"); }
            public void checkServerTrusted(X509Certificate[] chain, String auth) throws CertificateException {
                if (chain == null || chain.length == 0) throw new CertificateException("No receiver certificate");
                chain[0].checkValidity(); observed[0] = chain[0];
            }
        }}, null);
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(host, port), 2000);
            try (SSLSocket tls = (SSLSocket) context.getSocketFactory().createSocket(socket, host, port, true)) {
                tls.setSoTimeout(3000); tls.startHandshake();
                if (observed[0] == null) throw new CertificateException("No receiver certificate");
                return observed[0].getEncoded();
            }
        }
    }

    private SSLContext pinnedContext() throws GeneralSecurityException {
        final byte[] pin = MessageDigest.getInstance("SHA-256").digest(certificate);
        SSLContext context = SSLContext.getInstance("TLS");
        context.init(null, new TrustManager[]{new X509TrustManager() {
            public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
            public void checkClientTrusted(X509Certificate[] chain, String auth) throws CertificateException { throw new CertificateException("Not a server"); }
            public void checkServerTrusted(X509Certificate[] chain, String auth) throws CertificateException {
                if (chain == null || chain.length == 0) throw new CertificateException("No receiver certificate");
                chain[0].checkValidity();
                try {
                    if (!MessageDigest.isEqual(pin, MessageDigest.getInstance("SHA-256").digest(chain[0].getEncoded()))) throw new CertificateException("Receiver certificate changed");
                } catch (GeneralSecurityException error) { throw new CertificateException("Receiver certificate rejected"); }
            }
        }}, null);
        return context;
    }

    public String request(String path, String body, String token) throws IOException, GeneralSecurityException {
        if (!path.matches("/v1/FireTV(?:/pin/(?:display|verify)|/status|/keyboard|\\?action=(?:dpad_up|dpad_down|dpad_left|dpad_right|select|home|back))")) throw new IllegalArgumentException("Unsupported operation");
        if (token != null && (token.isEmpty() || token.length() > 4096 || !token.matches("[\\x20-\\x7e]+"))) throw new IllegalArgumentException("Invalid credential");
        HttpsURLConnection connection = (HttpsURLConnection) new URL("https", host, port, path).openConnection();
        try {
            connection.setSSLSocketFactory(pinnedContext().getSocketFactory());
            // Receiver is named by its exact certificate pin, not by a DNS hostname.
            connection.setHostnameVerifier((name, session) -> host.equals(name) && peerMatches(session));
            connection.setConnectTimeout(2000); connection.setReadTimeout(3000);
            connection.setInstanceFollowRedirects(false); connection.setUseCaches(false);
            connection.setRequestProperty("Content-Type", "application/json; charset=utf-8");
            connection.setRequestProperty("x-api-key", "0987654321"); // Public protocol identifier.
            if (token != null) connection.setRequestProperty("x-client-token", token);
            boolean post = !path.endsWith("/status");
            connection.setRequestMethod(post ? "POST" : "GET");
            if (post) {
                byte[] bytes = body == null ? new byte[0] : body.getBytes(StandardCharsets.UTF_8);
                if (bytes.length > 8192) throw new IOException("Request too large");
                connection.setDoOutput(true); connection.setFixedLengthStreamingMode(bytes.length);
                try (java.io.OutputStream stream = connection.getOutputStream()) { stream.write(bytes); }
            }
            int status = connection.getResponseCode();
            if (status < 200 || status >= 300) throw new HttpFailure(status);
            try (InputStream stream = connection.getInputStream(); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[4096]; int read;
                while ((read = stream.read(buffer)) != -1) {
                    if (output.size() + read > 65536) throw new IOException("Response too large");
                    output.write(buffer, 0, read);
                }
                return new String(output.toByteArray(), StandardCharsets.UTF_8);
            }
        } finally { connection.disconnect(); }
    }

    public void press(String action, String token) throws IOException, GeneralSecurityException {
        if (action == null || !action.matches("dpad_up|dpad_down|dpad_left|dpad_right|select|home|back")) throw new IllegalArgumentException("Unsupported input");
        String path = "/v1/FireTV?action=" + action;
        if ("home".equals(action) || "back".equals(action)) request(path, null, token);
        else {
            // A timeout can occur after the receiver accepted keyDown. Always release;
            // never retry keyDown, which could activate an item twice.
            try { request(path, "{\"keyActionType\":\"keyDown\"}", token); }
            finally { request(path, "{\"keyActionType\":\"keyUp\"}", token); }
        }
    }

    private boolean peerMatches(SSLSession session) {
        try { return MessageDigest.isEqual(certificate, session.getPeerCertificates()[0].getEncoded()); }
        catch (GeneralSecurityException | IOException error) { return false; }
    }
}
