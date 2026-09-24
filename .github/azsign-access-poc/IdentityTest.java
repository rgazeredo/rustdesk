import com.carriez.flutter_hbb.AzsignAccessIdentity;
import java.io.File;
import java.nio.file.Files;
import java.util.Base64;

public final class IdentityTest {
    public static void main(String[] args) throws Exception {
        AzsignAccessIdentity identity = new AzsignAccessIdentity(new File(args[1]));
        if ("prepare".equals(args[0])) {
            System.out.print(Base64.getEncoder().encodeToString(identity.prepare(args[2])));
        } else if ("verify".equals(args[0])) {
            identity.verifyCertificate(args[2], Files.readAllBytes(new File(args[3]).toPath()), Files.readAllBytes(new File(args[4]).toPath()));
            System.out.println("verified");
        } else throw new IllegalArgumentException("Unknown test operation");
    }
}
