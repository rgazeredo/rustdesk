package com.carriez.flutter_hbb;

import android.os.Process;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.InputEvent;
import android.view.KeyEvent;
import android.view.MotionEvent;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Method;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/** Private child process. No socket, shell commands, paths or text are accepted on stdin. */
public final class RootInputServer {
    private final Object manager;
    private final Method inject;
    private final Set<Integer> heldKeys = new HashSet<>();
    private long downTime;
    private long lastInput;
    private boolean touching;
    private float x, y;

    private RootInputServer() throws Exception {
        if (Process.myUid() != 0) throw new SecurityException("Root required");
        Class<?> type = Class.forName("android.hardware.input.InputManager");
        manager = type.getMethod("getInstance").invoke(null);
        inject = type.getMethod("injectInputEvent", InputEvent.class, int.class);
    }

    private void inject(InputEvent event) throws Exception {
        if (!Boolean.TRUE.equals(inject.invoke(manager, event, 2))) {
            throw new IllegalStateException("Input rejected");
        }
    }

    private void motion(int action, float px, float py) throws Exception {
        if (!Float.isFinite(px) || !Float.isFinite(py) || px < 0 || py < 0 || px > 8192 || py > 8192) {
            throw new IllegalArgumentException("Coordinates");
        }
        long now = SystemClock.uptimeMillis();
        if (action == MotionEvent.ACTION_DOWN) {
            if (touching) motion(MotionEvent.ACTION_CANCEL, x, y);
            downTime = now;
            touching = true;
        } else if (!touching) {
            return;
        }
        x = px;
        y = py;
        MotionEvent event = MotionEvent.obtain(downTime, now, action, x, y, 0);
        event.setSource(InputDevice.SOURCE_TOUCHSCREEN);
        try { inject(event); } finally { event.recycle(); }
        if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) touching = false;
        lastInput = now;
    }

    private void key(int action, int code, int meta) throws Exception {
        if ((action != 0 && action != 1) || code < 1 || code > KeyEvent.getMaxKeyCode() || meta < 0) {
            throw new IllegalArgumentException("Key");
        }
        long now = SystemClock.uptimeMillis();
        if (action == 0) heldKeys.add(code);
        inject(new KeyEvent(now, now, action, code, 0, meta, -1, 0, 0, InputDevice.SOURCE_KEYBOARD));
        if (action == 1) heldKeys.remove(code);
        lastInput = now;
    }

    private synchronized void release() throws Exception {
        if (touching) motion(MotionEvent.ACTION_CANCEL, x, y);
        for (int code : new HashSet<>(heldKeys)) key(1, code, 0);
    }

    private synchronized boolean command(String line) throws Exception {
        String[] p = line.split(" ");
        if (p.length == 1 && p[0].equals("Q")) return false;
        if (p.length == 1 && p[0].equals("R")) { release(); return true; }
        if (p.length == 4 && p[0].equals("M")) {
            int action = Integer.parseInt(p[1]);
            if (action < 0 || action > 3) throw new IllegalArgumentException("Motion action");
            motion(action, Float.parseFloat(p[2]), Float.parseFloat(p[3]));
        } else if (p.length == 4 && p[0].equals("K")) {
            key(Integer.parseInt(p[1]), Integer.parseInt(p[2]), Integer.parseInt(p[3]));
        } else if (p.length == 2 && p[0].equals("P")) {
            int code = Integer.parseInt(p[1]);
            key(0, code, 0);
            key(1, code, 0);
        } else {
            throw new IllegalArgumentException("Unknown command");
        }
        return true;
    }

    public static void main(String[] args) {
        RootInputServer server = null;
        ScheduledExecutorService watchdog = Executors.newSingleThreadScheduledExecutor();
        try {
            server = new RootInputServer();
            final RootInputServer current = server;
            // Network loss must not leave a finger or modifier held indefinitely.
            watchdog.scheduleAtFixedRate(() -> {
                synchronized (current) {
                    if (SystemClock.uptimeMillis() - current.lastInput > 2000) {
                        try { current.release(); } catch (Exception e) {
                            System.out.println("ERROR release");
                            System.exit(1);
                        }
                    }
                }
            }, 1, 1, TimeUnit.SECONDS);
            System.out.println("READY AZSIGN_ROOT_INPUT_1");
            BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
            String line;
            while ((line = input.readLine()) != null) {
                if (line.length() > 128) throw new IllegalArgumentException("Command length");
                if (!server.command(line)) break;
                System.out.println("OK");
            }
        } catch (Exception e) {
            System.out.println("ERROR " + e.getClass().getSimpleName());
        } finally {
            watchdog.shutdownNow();
            if (server != null) {
                try { server.release(); } catch (Exception e) { System.out.println("ERROR cleanup"); }
            }
        }
    }
}
