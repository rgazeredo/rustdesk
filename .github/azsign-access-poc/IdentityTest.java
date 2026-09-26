import com.carriez.flutter_hbb.AzsignAccessIdentity;
import java.io.File;
import java.nio.file.Files;
import java.util.Base64;
import java.security.*;
import java.security.interfaces.RSAPrivateKey;
import java.security.spec.*;
import java.math.BigInteger;

public final class IdentityTest {
    // Conscrypt on the DC400 decodes PKCS#8 to RSAPrivateKey, not RSAPrivateCrtKey.
    public static final class NonCrtFactory extends KeyFactorySpi {
        private KeyFactory delegate() throws NoSuchAlgorithmException, NoSuchProviderException {
            return KeyFactory.getInstance("RSA", "SunRsaSign");
        }
        protected PrivateKey engineGeneratePrivate(KeySpec spec) throws InvalidKeySpecException {
            try {
                final RSAPrivateKey key = (RSAPrivateKey) delegate().generatePrivate(spec);
                return new RSAPrivateKey() {
                    public BigInteger getModulus() { return key.getModulus(); }
                    public BigInteger getPrivateExponent() { return key.getPrivateExponent(); }
                    public String getAlgorithm() { return key.getAlgorithm(); }
                    public String getFormat() { return key.getFormat(); }
                    public byte[] getEncoded() { return key.getEncoded(); }
                };
            } catch (GeneralSecurityException error) { throw new InvalidKeySpecException(error); }
        }
        protected PublicKey engineGeneratePublic(KeySpec spec) throws InvalidKeySpecException {
            try { return delegate().generatePublic(spec); }
            catch (GeneralSecurityException error) { throw new InvalidKeySpecException(error); }
        }
        protected <T extends KeySpec> T engineGetKeySpec(Key key, Class<T> spec) throws InvalidKeySpecException {
            try { return delegate().getKeySpec(key, spec); }
            catch (GeneralSecurityException error) { throw new InvalidKeySpecException(error); }
        }
        protected Key engineTranslateKey(Key key) throws InvalidKeyException { return key; }
    }
    public static void main(String[] args) throws Exception {
        if ("prepare-noncrt".equals(args[0])) {
            Provider provider = new Provider("NonCrtRSA", "1.0", "Android non-CRT key regression") {};
            provider.put("KeyFactory.RSA", NonCrtFactory.class.getName());
            Security.insertProviderAt(provider, 1);
        }
        AzsignAccessIdentity identity = new AzsignAccessIdentity(new File(args[1]));
        if ("prepare".equals(args[0]) || "prepare-noncrt".equals(args[0])) {
            System.out.print(Base64.getEncoder().encodeToString(identity.prepare(args[2])));
        } else if ("verify".equals(args[0])) {
            identity.verifyCertificate(args[2], Files.readAllBytes(new File(args[3]).toPath()), Files.readAllBytes(new File(args[4]).toPath()));
            System.out.println("verified");
        } else throw new IllegalArgumentException("Unknown test operation");
    }
}
