package com.carriez.flutter_hbb;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.util.Base64;
import java.util.Random;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import org.json.JSONObject;

/**
 * Autonomous certificate renewal scheduler for AZSign remote access.
 * Manages background renewal lifecycle:
 * - Checks certificate expiration (fail-closed if expired / offline beyond validity).
 * - Schedules renewal at 75% of lifetime (e.g. 18h for 24h cert).
 * - Executes autonomous renewal with proof of local private key possession (reusing existing key).
 * - Performs atomic persistence of active.json without key rotation.
 * - Handles transient network failures with exponential backoff and randomized jitter.
 * - Stops immediately and fails closed upon revocation.
 * - Supports clean lifecycle cancellation.
 */
public final class AzsignRenewalScheduler {

    public enum State {
        IDLE,
        SCHEDULED,
        RENEWING,
        RENEWED,
        FAILED_RETRYING,
        REVOKED,
        EXPIRED,
        STOPPED
    }

    public static class RevokedException extends Exception {
        public RevokedException(String message) { super(message); }
    }

    public static class BlockedException extends Exception {
        public BlockedException(String message) { super(message); }
    }

    public interface RenewalTransport {
        /**
         * Requests a single-use renewal challenge from CMS for the identity.
         */
        String requestChallenge(String identityId) throws Exception;

        /**
         * Submits CSR and challenge proof to CMS.
         * Returns renewed certificate (DER), CA certificate (DER), and updated profile (JSON).
         * Revocation is permanent; temporary blocks MUST NOT be mapped to revocation.
         * Throw BlockedException for a temporary block (preserve enrollment and retry).
         */
        RenewalPayload submitRenewal(String identityId, byte[] csrDer, String challenge, String challengeProof) throws Exception;
    }

    public static final class RenewalPayload {
        public final byte[] certificate;
        public final byte[] ca;
        public final JSONObject profile;

        public RenewalPayload(byte[] certificate, byte[] ca, JSONObject profile) {
            this.certificate = certificate;
            this.ca = ca;
            this.profile = profile;
        }
    }

    private final File directory;
    private final AzsignAccessIdentity identity;
    private final RenewalTransport transport;
    private final ScheduledExecutorService executor;
    private final Random random;

    private final AtomicReference<State> state = new AtomicReference<>(State.IDLE);
    private final AtomicBoolean running = new AtomicBoolean(false);
    private ScheduledFuture<?> scheduledTask = null;

    private long baseRetryDelayMs = 60_000L; // 1 minute
    private long maxRetryDelayMs = 3_600_000L; // 1 hour
    private int consecutiveFailures = 0;
    private long nextScheduledAttemptMs = 0L;

    public AzsignRenewalScheduler(File directory, RenewalTransport transport) {
        this(directory, transport, Executors.newSingleThreadScheduledExecutor());
    }

    public AzsignRenewalScheduler(File directory, RenewalTransport transport, ScheduledExecutorService executor) {
        this.directory = directory;
        this.identity = new AzsignAccessIdentity(directory);
        this.transport = transport;
        this.executor = executor;
        this.random = new Random();
    }

    public void setRetryDelays(long baseMs, long maxMs) {
        this.baseRetryDelayMs = baseMs;
        this.maxRetryDelayMs = maxMs;
    }

    public synchronized void start() {
        if (running.getAndSet(true)) return;
        evaluateAndSchedule();
    }

    public synchronized void stop() {
        running.set(false);
        if (scheduledTask != null) {
            scheduledTask.cancel(true);
            scheduledTask = null;
        }
        if (state.get() != State.REVOKED) {
            state.set(State.STOPPED);
        }
    }

    public State getState() {
        return state.get();
    }

    public long getNextScheduledAttemptMs() {
        return nextScheduledAttemptMs;
    }

    public int getConsecutiveFailures() {
        return consecutiveFailures;
    }

    /**
     * Determines whether remote transport is authorized based on active enrollment validity.
     * Returns false if certificate is missing, expired, or device is revoked.
     */
    public boolean isRemoteTransportAuthorized() {
        if (state.get() == State.REVOKED) return false;
        try {
            File activeFile = new File(directory, "active.json");
            if (!activeFile.exists()) return false;
            byte[] bytes = AzsignAccessIdentity.readLimited(activeFile, 32768);
            JSONObject active = new JSONObject(new String(bytes, StandardCharsets.UTF_8));
            byte[] certDer = Base64.getDecoder().decode(active.getString("certificate_base64"));
            X509Certificate cert = parseCertificate(certDer);
            cert.checkValidity();
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Inspects active.json and calculates schedule delay until renewal window.
     * Default policy: renew at 75% of certificate lifetime, or immediately if past window.
     */
    public synchronized void evaluateAndSchedule() {
        if (!running.get()) return;

        try {
            File activeFile = new File(directory, "active.json");
            if (!activeFile.exists()) {
                state.set(State.IDLE);
                return;
            }

            byte[] bytes = AzsignAccessIdentity.readLimited(activeFile, 32768);
            JSONObject active = new JSONObject(new String(bytes, StandardCharsets.UTF_8));
            byte[] certDer = Base64.getDecoder().decode(active.getString("certificate_base64"));
            X509Certificate cert = parseCertificate(certDer);

            long now = System.currentTimeMillis();
            long notBefore = cert.getNotBefore().getTime();
            long notAfter = cert.getNotAfter().getTime();

            if (now >= notAfter) {
                state.set(State.EXPIRED);
                // Expired: attempt renewal immediately, but remote transport remains disabled until renewed
                scheduleExecution(0);
                return;
            }

            long totalLifetime = Math.max(1, notAfter - notBefore);
            long renewalTarget = notBefore + (long) (totalLifetime * 0.75); // 75% mark
            long delay = Math.max(0, renewalTarget - now);

            state.set(State.SCHEDULED);
            scheduleExecution(delay);
        } catch (Exception e) {
            state.set(State.FAILED_RETRYING);
            scheduleRetry();
        }
    }

    private synchronized void scheduleExecution(long delayMs) {
        if (!running.get()) return;
        if (scheduledTask != null) {
            scheduledTask.cancel(false);
        }
        nextScheduledAttemptMs = System.currentTimeMillis() + delayMs;
        scheduledTask = executor.schedule(this::runRenewalCycle, delayMs, TimeUnit.MILLISECONDS);
    }

    private synchronized void scheduleRetry() {
        if (!running.get() || state.get() == State.REVOKED) return;

        consecutiveFailures++;
        long backoff = baseRetryDelayMs * (1L << Math.min(consecutiveFailures - 1, 10));
        long boundedBackoff = Math.min(backoff, maxRetryDelayMs);

        // Apply ±20% randomized jitter
        double jitterFactor = 0.8 + (random.nextDouble() * 0.4);
        long delayWithJitter = Math.max(100L, (long) (boundedBackoff * jitterFactor));

        state.set(State.FAILED_RETRYING);
        scheduleExecution(delayWithJitter);
    }

    /**
     * Executes the renewal process:
     * 1. Reads current active enrollment and identity ID.
     * 2. Requests challenge from CMS.
     * 3. Generates CSR from local key (preserving key.der).
     * 4. Submits renewal request to CMS.
     * 5. Validates returned certificate with local identity and CA.
     * 6. Commits new active.json atomically.
     */
    public synchronized boolean performRenewalNow() throws Exception {
        state.set(State.RENEWING);

        File activeFile = new File(directory, "active.json");
        if (!activeFile.exists()) throw new FileNotFoundException("active.json not found");
        byte[] bytes = AzsignAccessIdentity.readLimited(activeFile, 32768);
        JSONObject active = new JSONObject(new String(bytes, StandardCharsets.UTF_8));
        String identityId = active.getString("identity_id");

        // 1. Challenge
        String challenge = transport.requestChallenge(identityId);

        // 2. CSR generated from existing key
        byte[] csrDer = identity.prepare(identityId);

        // 3. Submit renewal
        String proof = identity.signRenewal(identityId, challenge, csrDer);
        RenewalPayload payload = transport.submitRenewal(identityId, csrDer, challenge, proof);

        // 4. Verify certificate strictly against identity and CA
        byte[] enrolledCa = Base64.getDecoder().decode(active.getString("ca_base64"));
        if (!java.security.MessageDigest.isEqual(enrolledCa, payload.ca)) {
            throw new SecurityException("Renewal cannot replace the enrolled authority");
        }
        if (!active.getJSONObject("profile").similar(payload.profile)) {
            throw new SecurityException("Renewal cannot replace the enrolled gateway profile");
        }
        X509Certificate renewedLeaf = identity.verifyCertificate(identityId, payload.certificate, enrolledCa);
        X509Certificate previousLeaf = parseCertificate(Base64.getDecoder().decode(active.getString("certificate_base64")));
        if (!renewedLeaf.getNotAfter().after(previousLeaf.getNotAfter())) {
            throw new SecurityException("Renewal must extend certificate validity");
        }

        // 5. Atomic persist
        JSONObject newActive = new JSONObject(active.toString());
        newActive.put("identity_id", identityId);
        newActive.put("profile", payload.profile);
        newActive.put("certificate_base64", Base64.getEncoder().encodeToString(payload.certificate));
        newActive.put("ca_base64", Base64.getEncoder().encodeToString(payload.ca));
        newActive.put("expires_at", renewedLeaf.getNotAfter().getTime());

        writeAtomic(activeFile, newActive.toString().getBytes(StandardCharsets.UTF_8));

        consecutiveFailures = 0;
        state.set(State.RENEWED);
        return true;
    }

    public synchronized void handleRevoked() {
        state.set(State.REVOKED);
        File activeFile = new File(directory, "active.json");
        if (activeFile.exists()) activeFile.delete();
        stop();
    }

    public void runRenewalCycle() {
        if (!running.get()) return;

        try {
            performRenewalNow();
            // Reschedule next regular renewal based on the new certificate
            evaluateAndSchedule();
        } catch (RevokedException revoked) {
            handleRevoked();
        } catch (Throwable error) {
            scheduleRetry();
        }
    }

    private static X509Certificate parseCertificate(byte[] der) throws Exception {
        CertificateFactory factory = CertificateFactory.getInstance("X.509");
        return (X509Certificate) factory.generateCertificate(new ByteArrayInputStream(der));
    }

    public static void writeAtomic(File target, byte[] bytes) throws IOException {
        File parent = target.getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw new IOException("Cannot create directory: " + parent);
        }
        File temp = new File(parent, target.getName() + ".tmp." + System.nanoTime());
        try (FileOutputStream out = new FileOutputStream(temp)) {
            out.write(bytes);
            out.getFD().sync();
        }
        if (!temp.renameTo(target)) {
            temp.delete();
            throw new IOException("Failed to atomically commit file: " + target);
        }
    }
}
