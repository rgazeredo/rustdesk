package com.carriez.flutter_hbb;

import java.io.File;
import java.net.URL;
import javax.net.ssl.HttpsURLConnection;

/** Real HTTPS, real CMS. Only the test port is remapped; normal TLS verification stays enabled. */
public final class RenewalLiveTest {
    public static void main(String[] args) throws Exception {
        File dir = new File(args[0]);
        String id = args[1];
        AzsignAccessIdentity identity = new AzsignAccessIdentity(dir);
        AzsignRenewalHttp http = new AzsignRenewalHttp(dir, "https://localhost",
            url -> (HttpsURLConnection) new URL("https://localhost:" + args[2] + url.getFile()).openConnection());
        byte[] csr = identity.prepare(id);
        String challenge = http.requestChallenge(id);
        try {
            AzsignRenewalScheduler.RenewalPayload result = http.submitRenewal(id, csr, challenge, identity.signRenewal(id, challenge, csr));
            identity.verifyCertificate(id, result.certificate, result.ca);
            if (!"allow".equals(args[3])) throw new AssertionError("Blocked device renewed");
            System.out.println("https-renewal-verified");
        } catch (AzsignRenewalScheduler.BlockedException expected) {
            if (!"block".equals(args[3])) throw expected;
            if (!new File(dir, "active.json").exists()) throw new AssertionError("Enrollment lost");
            System.out.println("https-block-verified");
        }
    }
}
