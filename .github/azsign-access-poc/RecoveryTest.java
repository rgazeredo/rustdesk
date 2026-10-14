package com.carriez.flutter_hbb;

import java.io.*;
import java.nio.file.*;
import java.util.Base64;
import org.json.JSONObject;

public class RecoveryTest {
    static void check(boolean value, String message) { if (!value) throw new AssertionError(message); }
    public static void main(String[] args) throws Exception {
        File dir = new File(args[0]);
        String id = args[1];
        JSONObject active = new JSONObject(new String(Files.readAllBytes(new File(dir,"active.json").toPath())));
        // Recovery can run before MainService/Flutter has initialized Config.
        // An unavailable ID must not issue a request, replace credentials or
        // manufacture a new identity. A later tick resumes with the saved ID.
        byte[] savedActive = Files.readAllBytes(new File(dir,"active.json").toPath());
        byte[] savedKey = Files.readAllBytes(new File(dir,"identity/key.der").toPath());
        final boolean[] configReady = {false};
        final int[] requests = {0};
        AzsignRecovery early = new AzsignRecovery(dir, new AzsignRecovery.Native() {
            public String deviceId() { return configReady[0] ? "1465886383" : ""; }
            public boolean setPassword(String value) { throw new AssertionError("Boot must not replace password"); }
            public void restartTransport() { throw new AssertionError("Boot must not restart transport"); }
        }, "https://cms.test");
        AzsignRecovery.Transport waiting = (operation, body) -> {
            requests[0]++;
            if (operation.equals("challenge")) return new JSONObject().put("challenge", "A".repeat(43)).put("expires_in", 120);
            check(body.getString("remote_id").equals("1465886383"), "Resume with persisted ID");
            return new JSONObject().put("status", "waiting");
        };
        for (int i = 0; i < 3; i++) early.cycle(id, active, waiting);
        check(requests[0] == 0 && early.status().getString("state").equals("WAITING_ID"), "Wait for native configuration before recovery");
        configReady[0] = true;
        early.cycle(id, active, waiting);
        check(requests[0] == 2 && early.status().getString("state").equals("WAITING"), "Recovery resumes after configuration initialization");
        check(java.util.Arrays.equals(savedActive, Files.readAllBytes(new File(dir,"active.json").toPath())), "Startup preserves certificate/profile");
        check(java.util.Arrays.equals(savedKey, Files.readAllBytes(new File(dir,"identity/key.der").toPath())), "Startup preserves identity key");
        check(!new File(dir,"recovery-pending.json").exists(), "Startup must not create recovery grant");
        early.close();
        JSONObject authorized = new JSONObject(active.toString()).put("status","authorized")
            .put("grant_id","0199a000-0000-7000-8000-000000000099").put("password","abcdefghijklmnopqrstuv12");
        java.security.cert.X509Certificate leaf = (java.security.cert.X509Certificate) java.security.cert.CertificateFactory.getInstance("X.509").generateCertificate(new ByteArrayInputStream(Base64.getDecoder().decode(active.getString("certificate_base64"))));
        authorized.put("expires_at", leaf.getNotAfter().getTime());
        final int[] applied = {0}; final int[] restarted = {0}; final boolean[] failReceipt = {true};
        AzsignRecovery.Native bridge = new AzsignRecovery.Native() {
            public String deviceId() { return "1465886383"; }
            public boolean setPassword(String value) { applied[0]++; return value.equals(authorized.optString("password")); }
            public void restartTransport() { restarted[0]++; }
        };
        AzsignRecovery recovery = new AzsignRecovery(dir, bridge, "https://cms.test");
        JSONObject context = recovery.context();
        check(new File(dir,"recovery.json").isFile(),"Independent recovery context persists");
        new File(dir,"active.json").delete();
        AzsignRecovery.Transport transport = (operation,body) -> {
            if(operation.equals("challenge")) return new JSONObject().put("challenge","A".repeat(43)).put("expires_in",120);
            check(body.getString("remote_id").equals("1465886383"),"Signed remote ID");
            byte[] csrBytes = Base64.getDecoder().decode(body.getString("csr_base64"));
            StringBuilder hash = new StringBuilder();
            for (byte value : java.security.MessageDigest.getInstance("SHA-256").digest(csrBytes)) hash.append(String.format("%02x", value & 255));
            String message = String.join("\n", "AZSIGN-DEVICE-RECOVERY-V1", id, body.getString("phase"), body.optString("grant_id", "-"), "1465886383", body.getString("challenge"), hash.toString());
            java.security.Signature verifier = java.security.Signature.getInstance("SHA256withRSA");
            verifier.initVerify(leaf.getPublicKey()); verifier.update(message.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            check(verifier.verify(Base64.getDecoder().decode(body.getString("proof_base64"))),"Canonical recovery proof verifies against registered public key");
            if(body.getString("phase").equals("prepare")) return new JSONObject(authorized.toString());
            if(failReceipt[0]) throw new IOException("lost response");
            return new JSONObject().put("status","completed");
        };
        try { recovery.cycle(id,context,transport); throw new AssertionError("Receipt failure must retry"); } catch(IOException expected) {}
        check(applied[0]==1 && restarted[0]==0,"Not completed before receipt");
        String journal = new String(Files.readAllBytes(new File(dir,"recovery-pending.json").toPath()));
        check(!journal.contains(authorized.getString("password")),"No password in recovery journal");
        failReceipt[0]=false;
        recovery.cycle(id,context,transport);
        check(applied[0]==1 && restarted[0]==1,"Lost receipt retry is idempotent");
        check(!new File(dir,"recovery-pending.json").exists(),"Receipt journal removed");
        AzsignRenewalRuntime.stop(); recovery.close();
        JSONObject expired = new JSONObject(authorized.toString());
        expired.remove("password"); expired.put("expires_at", 1);
        AzsignRecovery.write(new File(dir,"recovery-pending.json"), expired);
        AzsignRecovery retry = new AzsignRecovery(dir, bridge, "https://cms.test");
        retry.cycle(id,context,transport);
        check(applied[0]==2 && restarted[0]==2,"Expired pending certificate requests a fresh preparation");
        AzsignRenewalRuntime.stop(); retry.close();
        // No access credential after revocation: remaining private key still authenticates recovery.
        new File(dir,"active.json").delete();
        final boolean[] wrote = {false};
        AzsignRecovery refusing = new AzsignRecovery(dir,new AzsignRecovery.Native(){
            public String deviceId(){return "1465886383";}
            public boolean setPassword(String value){wrote[0]=true;return false;}
            public void restartTransport(){throw new AssertionError("Must not enable on failed password");}
        },"https://cms.test");
        try { refusing.cycle(id,new JSONObject(),transport); throw new AssertionError("Missing password receipt"); } catch(IOException expected) {}
        check(wrote[0] && !new File(dir,"active.json").exists(),"Password failure cannot enable transport");
        refusing.close();
        System.out.println("recovery-verified");
    }
}
