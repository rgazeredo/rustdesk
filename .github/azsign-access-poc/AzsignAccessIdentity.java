package com.carriez.flutter_hbb;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.security.interfaces.RSAPrivateCrtKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.RSAPublicKeySpec;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.util.Arrays;
import java.util.UUID;
import org.bouncycastle.asn1.x500.X500Name;
import org.bouncycastle.pkcs.jcajce.JcaPKCS10CertificationRequestBuilder;
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder;

/** Private, exportable software key for the pilot. Not a hardware-backed key. */
public final class AzsignAccessIdentity {
    private final File directory;
    public AzsignAccessIdentity(File directory) { this.directory = directory; }

    public static String identityId(String value) {
        if (value == null || !value.matches("[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}")) {
            throw new IllegalArgumentException("Invalid identity UUID");
        }
        return UUID.fromString(value).toString();
    }

    public synchronized byte[] prepare(String value) throws Exception {
        String id = identityId(value);
        File identity = new File(directory, "identity");
        if (!identity.exists()) {
            if (!directory.isDirectory() && !directory.mkdirs()) throw new IOException("Private directory unavailable");
            File staging = new File(directory, "enroll-" + UUID.randomUUID());
            if (!staging.mkdir()) throw new IOException("Cannot prepare identity");
            try {
                KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
                generator.initialize(2048, new SecureRandom());
                KeyPair pair = generator.generateKeyPair();
                writePrivate(new File(staging, "key.der"), pair.getPrivate().getEncoded());
                writePrivate(new File(staging, "id"), id.getBytes(StandardCharsets.US_ASCII));
                if (!staging.renameTo(identity)) throw new IOException("Cannot commit identity");
            } finally {
                if (staging.exists()) {
                    new File(staging, "key.der").delete();
                    new File(staging, "id").delete();
                    staging.delete();
                }
            }
        }
        KeyPair pair = load(id);
        return new JcaPKCS10CertificationRequestBuilder(new X500Name("CN=" + id), pair.getPublic())
            .build(new JcaContentSignerBuilder("SHA256withRSA").build(pair.getPrivate())).getEncoded();
    }

    private KeyPair load(String id) throws Exception {
        File identity = new File(directory, "identity");
        String saved = new String(readLimited(new File(identity, "id"), 36), StandardCharsets.US_ASCII);
        if (!identityId(id).equals(saved)) throw new SecurityException("Device is enrolled to another identity");
        RSAPrivateCrtKey key = (RSAPrivateCrtKey) KeyFactory.getInstance("RSA").generatePrivate(
            new PKCS8EncodedKeySpec(readLimited(new File(identity, "key.der"), 8192)));
        if (key.getModulus().bitLength() != 2048) throw new SecurityException("Unexpected key size");
        PublicKey pub = KeyFactory.getInstance("RSA").generatePublic(new RSAPublicKeySpec(key.getModulus(), key.getPublicExponent()));
        return new KeyPair(pub, key);
    }

    public void verifyCertificate(String id, byte[] certificate, byte[] authority) throws Exception {
        KeyPair pair = load(id);
        CertificateFactory factory = CertificateFactory.getInstance("X.509");
        X509Certificate leaf = (X509Certificate) factory.generateCertificate(new ByteArrayInputStream(certificate));
        X509Certificate ca = (X509Certificate) factory.generateCertificate(new ByteArrayInputStream(authority));
        leaf.checkValidity();
        ca.checkValidity();
        if (leaf.getBasicConstraints() != -1 || ca.getBasicConstraints() < 0
            || !leaf.getIssuerX500Principal().equals(ca.getSubjectX500Principal())
            || leaf.getExtendedKeyUsage() == null || !leaf.getExtendedKeyUsage().contains("1.3.6.1.5.5.7.3.2")
            || leaf.getKeyUsage() == null || !leaf.getKeyUsage()[0]
            || (ca.getKeyUsage() != null && !ca.getKeyUsage()[5])
            || !new X500Name("CN=" + identityId(id)).equals(X500Name.getInstance(leaf.getSubjectX500Principal().getEncoded()))
            || !Arrays.equals(pair.getPublic().getEncoded(), leaf.getPublicKey().getEncoded())) {
            throw new SecurityException("Certificate does not authorize this identity");
        }
        leaf.verify(ca.getPublicKey());
    }

    public static byte[] readLimited(File path, int maximum) throws IOException {
        try (InputStream input = new FileInputStream(path); ByteArrayOutputStream result = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[1024];
            int size;
            while ((size = input.read(buffer)) != -1) {
                if (result.size() + size > maximum) throw new IOException("Oversized private file");
                result.write(buffer, 0, size);
            }
            return result.toByteArray();
        }
    }

    public static void writePrivate(File path, byte[] bytes) throws IOException {
        if (!path.createNewFile()) throw new IOException("Refusing to replace private file");
        if (!path.setReadable(false, false) || !path.setWritable(false, false)
            || !path.setReadable(true, true) || !path.setWritable(true, true)) throw new IOException("Private permissions unavailable");
        try (FileOutputStream output = new FileOutputStream(path)) {
            output.write(bytes);
            output.getFD().sync();
        }
    }
}
