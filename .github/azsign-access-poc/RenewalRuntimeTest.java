import com.carriez.flutter_hbb.AzsignRenewalRuntime;
import com.carriez.flutter_hbb.AzsignRenewalScheduler;
import java.io.File;
import java.lang.reflect.Field;
import java.nio.file.Files;
import java.util.Arrays;

public final class RenewalRuntimeTest {
    public static void main(String[] args) throws Exception {
        File files = new File(args[0]);
        File active = new File(files, "azsign-access-poc/active.json");
        byte[] before = Files.readAllBytes(active.toPath());
        Field field = AzsignRenewalRuntime.class.getDeclaredField("scheduler");
        field.setAccessible(true);
        try {
            AzsignRenewalRuntime.start(files);
            AzsignRenewalScheduler first = (AzsignRenewalScheduler) field.get(null);
            if (first == null || first.getState() != AzsignRenewalScheduler.State.SCHEDULED) throw new AssertionError("Startup did not resume certificate schedule");
            org.json.JSONObject status = AzsignRenewalRuntime.status(files);
            if (!status.getBoolean("enrolled") || !status.getBoolean("transport_authorized")) throw new AssertionError("Missing runtime diagnostics");
            if (status.has("certificate_base64") || status.has("identity_id") || status.has("key") || status.has("renewal_origin")) throw new AssertionError("Diagnostics exposed enrollment material");
            AzsignRenewalRuntime.start(files);
            if (field.get(null) != first) throw new AssertionError("Duplicate scheduler");
            AzsignRenewalRuntime.stop();
            if (first.getState() != AzsignRenewalScheduler.State.STOPPED || field.get(null) != null) throw new AssertionError("Failed to stop");
            AzsignRenewalRuntime.start(files);
            if (field.get(null) == null || field.get(null) == first) throw new AssertionError("Restart did not restore from disk");
            if (!Arrays.equals(before, Files.readAllBytes(active.toPath()))) throw new AssertionError("Restart changed enrollment");
        } finally { AzsignRenewalRuntime.stop(); }
        System.out.println("runtime-verified");
    }
}
