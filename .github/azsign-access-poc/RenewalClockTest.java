import com.carriez.flutter_hbb.AzsignRenewalScheduler;
import java.io.File;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;

public final class RenewalClockTest {
    private static final class Timer extends ScheduledThreadPoolExecutor {
        Runnable pending;
        long delay;
        Timer() { super(1); }
        @Override public ScheduledFuture<?> schedule(Runnable task, long value, TimeUnit unit) {
            pending = task;
            delay = unit.toMillis(value);
            return super.schedule(() -> {}, 3650, TimeUnit.DAYS);
        }
    }

    public static void main(String[] args) throws Exception {
        File dir = new File(args[0]);
        byte[] before = Files.readAllBytes(new File(dir, "active.json").toPath());
        long[] now = { 1_600_000_000_000L };
        Timer timer = new Timer();
        AzsignRenewalScheduler.RenewalTransport transport = new AzsignRenewalScheduler.RenewalTransport() {
            public String requestChallenge(String id) { throw new AssertionError("No network before renewal time"); }
            public AzsignRenewalScheduler.RenewalPayload submitRenewal(String id, byte[] csr, String nonce, String proof) {
                throw new AssertionError("No network before renewal time");
            }
        };
        AzsignRenewalScheduler scheduler = new AzsignRenewalScheduler(dir, transport, timer, () -> now[0]);
        try {
            scheduler.start();
            if (timer.delay > 60_000 || timer.delay <= 0) throw new AssertionError("Boot clock scheduled unbounded wait");
            now[0] = System.currentTimeMillis() + TimeUnit.DAYS.toMillis(3);
            timer.pending.run();
            if (timer.delay != 0) throw new AssertionError("NTP correction did not trigger expired certificate recovery");
            now[0] = 1_500_000_000_000L;
            scheduler.evaluateAndSchedule();
            if (timer.delay > 60_000 || timer.delay <= 0) throw new AssertionError("Backward correction scheduled unbounded wait");
            if (!Arrays.equals(before, Files.readAllBytes(new File(dir, "active.json").toPath()))) throw new AssertionError("Scheduling modified enrollment");
            System.out.println("clock-verified");
        } finally { scheduler.close(); }
    }
}
