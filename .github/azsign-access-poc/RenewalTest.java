import com.carriez.flutter_hbb.AzsignAccessIdentity;
import com.carriez.flutter_hbb.AzsignRenewalScheduler;
import com.carriez.flutter_hbb.AzsignRenewalScheduler.RenewalPayload;
import com.carriez.flutter_hbb.AzsignRenewalScheduler.RenewalTransport;
import com.carriez.flutter_hbb.AzsignRenewalScheduler.RevokedException;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.Base64;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.security.Signature;
import java.security.cert.CertificateFactory;
import java.io.ByteArrayInputStream;
import org.json.JSONObject;

public final class RenewalTest {

    public static void main(String[] args) throws Exception {
        String command = args[0];
        File dir = new File(args[1]);
        String identityId = args[2];

        if ("test-success".equals(command) || "test-profile-change".equals(command) || "test-ca-change".equals(command) || "test-replay".equals(command)) {
            byte[] before = Files.readAllBytes(new File(dir, "active.json").toPath());
            byte[] initialKey = Files.readAllBytes(new File(dir, "identity/key.der").toPath());
            byte[] renewedCert = Files.readAllBytes(new File(args[3]).toPath());
            byte[] caCert = Files.readAllBytes(new File(args[4]).toPath());

            RenewalTransport mockTransport = new RenewalTransport() {
                @Override
                public String requestChallenge(String id) {
                    if (!identityId.equals(id)) throw new IllegalArgumentException("Mismatch id");
                    return "single-use-challenge-nonce";
                }

                @Override
                public RenewalPayload submitRenewal(String id, byte[] csrDer, String challenge, String challengeProof) throws Exception {
                    if (!identityId.equals(id)) throw new IllegalArgumentException("Mismatch id");
                    if (csrDer == null || csrDer.length == 0) throw new IllegalArgumentException("Empty CSR");
                    Signature verifier = Signature.getInstance("SHA256withRSA");
                    verifier.initVerify(CertificateFactory.getInstance("X.509").generateCertificate(new ByteArrayInputStream(renewedCert)));
                    verifier.update(AzsignAccessIdentity.renewalMessage(id, challenge, csrDer));
                    if (!verifier.verify(Base64.getDecoder().decode(challengeProof))) throw new AssertionError("Missing challenge proof");
                    verifier.update(AzsignAccessIdentity.renewalMessage(id, challenge + "-other", csrDer));
                    if (verifier.verify(Base64.getDecoder().decode(challengeProof))) throw new AssertionError("Proof does not bind nonce");
                    JSONObject profile = new JSONObject();
                    profile.put("host", "rustdesk.azsign.com.br");
                    profile.put("server_name", "rustdesk.azsign.com.br");
                    profile.put("registration", 32116);
                    profile.put("rendezvous", 32117);
                    profile.put("relay", 32118);
                    if ("test-profile-change".equals(command)) profile.put("host", "attacker.invalid");
                    byte[] returnedCa = caCert.clone();
                    if ("test-ca-change".equals(command)) returnedCa[0] ^= 1;
                    return new RenewalPayload(renewedCert, returnedCa, profile);
                }
            };

            ScheduledExecutorService exec = Executors.newSingleThreadScheduledExecutor();
            try {
                AzsignRenewalScheduler scheduler = new AzsignRenewalScheduler(dir, mockTransport, exec);
                if (!scheduler.isRemoteTransportAuthorized()) throw new AssertionError("Should be authorized initially");

                boolean ok;
                try {
                    ok = scheduler.performRenewalNow();
                    if (!"test-success".equals(command)) throw new AssertionError("Unsafe renewal accepted");
                } catch (SecurityException rejected) {
                    if ("test-success".equals(command)) throw rejected;
                    if (!Arrays.equals(before, Files.readAllBytes(new File(dir, "active.json").toPath()))) throw new AssertionError("Enrollment changed on rejection");
                    System.out.println("rejected-verified");
                    return;
                }
                if (!ok) throw new AssertionError("Renewal failed");
                if (scheduler.getState() != AzsignRenewalScheduler.State.RENEWED) throw new AssertionError("State not RENEWED");

                // Verify key is retained
                byte[] keyAfter = Files.readAllBytes(new File(dir, "identity/key.der").toPath());
                if (!Arrays.equals(initialKey, keyAfter)) throw new AssertionError("Key must be preserved during renewal");

                // Verify active.json updated
                JSONObject active = new JSONObject(new String(Files.readAllBytes(new File(dir, "active.json").toPath()), StandardCharsets.UTF_8));
                byte[] savedCert = Base64.getDecoder().decode(active.getString("certificate_base64"));
                if (!Arrays.equals(renewedCert, savedCert)) throw new AssertionError("Active cert not updated");
                if (!scheduler.isRemoteTransportAuthorized()) throw new AssertionError("Should remain authorized");

                System.out.println("success-verified");
            } finally {
                exec.shutdownNow();
            }
        } else if ("test-blocked".equals(command)) {
            byte[] before = Files.readAllBytes(new File(dir, "active.json").toPath());
            RenewalTransport blocked = new RenewalTransport() {
                public String requestChallenge(String id) throws Exception {
                    throw new AzsignRenewalScheduler.BlockedException("Temporarily blocked");
                }
                public RenewalPayload submitRenewal(String id, byte[] csr, String nonce, String proof) {
                    throw new AssertionError("No issuance while blocked");
                }
            };
            ScheduledExecutorService exec = Executors.newSingleThreadScheduledExecutor();
            try {
                AzsignRenewalScheduler scheduler = new AzsignRenewalScheduler(dir, blocked, exec);
                scheduler.start();
                scheduler.runRenewalCycle();
                if (scheduler.getState() != AzsignRenewalScheduler.State.FAILED_RETRYING) throw new AssertionError("Block must retry");
                if (!Arrays.equals(before, Files.readAllBytes(new File(dir, "active.json").toPath()))) throw new AssertionError("Block erased enrollment");
                scheduler.stop();
                System.out.println("blocked-verified");
            } finally { exec.shutdownNow(); }
        } else if ("test-revoked".equals(command)) {
            RenewalTransport revokedTransport = new RenewalTransport() {
                @Override
                public String requestChallenge(String id) throws Exception {
                    throw new RevokedException("Device revoked on CMS");
                }
                @Override
                public RenewalPayload submitRenewal(String id, byte[] csrDer, String challenge, String challengeProof) throws Exception {
                    throw new RevokedException("Device revoked on CMS");
                }
            };

            ScheduledExecutorService exec = Executors.newSingleThreadScheduledExecutor();
            try {
                AzsignRenewalScheduler scheduler = new AzsignRenewalScheduler(dir, revokedTransport, exec);
                scheduler.start();
                scheduler.runRenewalCycle();

                if (scheduler.getState() != AzsignRenewalScheduler.State.REVOKED) {
                    throw new AssertionError("State should be REVOKED, got: " + scheduler.getState());
                }
                if (scheduler.isRemoteTransportAuthorized()) {
                    throw new AssertionError("Remote transport must NOT be authorized when revoked");
                }
                if (new File(dir, "active.json").exists()) {
                    throw new AssertionError("active.json must be deleted when revoked");
                }

                System.out.println("revoked-verified");
            } finally {
                exec.shutdownNow();
            }
        } else if ("test-expired".equals(command)) {
            ScheduledExecutorService exec = Executors.newSingleThreadScheduledExecutor();
            try {
                AzsignRenewalScheduler scheduler = new AzsignRenewalScheduler(dir, null, exec);
                if (scheduler.isRemoteTransportAuthorized()) {
                    throw new AssertionError("Expired cert must NOT authorize remote transport");
                }
                System.out.println("expired-verified");
            } finally {
                exec.shutdownNow();
            }
        } else throw new IllegalArgumentException("Unknown command: " + command);
    }
}
