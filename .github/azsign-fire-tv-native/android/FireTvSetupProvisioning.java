package com.carriez.flutter_hbb;

import android.content.Context;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;
import android.os.SystemClock;
import android.system.Os;
import android.system.OsConstants;
import android.system.StructPollfd;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

/** Shell-authorized setup only. Receipts never export PINs, certificates or tokens. */
public final class FireTvSetupProvisioning {
    private static final long TTL = 150000;
    private static Session current;
    private static final class Session {
        final String id;
        final long until = SystemClock.elapsedRealtime() + TTL;
        String state = "starting";
        Session(String id) { this.id = id; }
    }
    private static boolean validId(String id) {
        return id != null && id.matches("[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}");
    }
    private static boolean active(Session s) { return current == s && SystemClock.elapsedRealtime() < s.until; }
    private static synchronized void state(Session s, String state) { if (active(s)) s.state = state; }

    public static synchronized Bundle call(Context context, String method, String id) {
        if (!validId(id)) throw new IllegalArgumentException("Invalid setup request");
        Bundle reply = new Bundle();
        reply.putInt("protocol", 1);
        reply.putBoolean("supported", FireTvNativeRemote.isTarget());
        reply.putString("request_id", id);
        if (!FireTvNativeRemote.isTarget()) { reply.putString("status", "unsupported"); return reply; }
        FireTvNativeRemote remote = FireTvNativeRemote.get(context);
        if ("fire-tv-begin".equals(method)) {
            if (current != null && active(current) && !current.id.equals(id) &&
                    ("starting".equals(current.state) || "pin-ready".equals(current.state) || "verifying".equals(current.state))) {
                reply.putString("status", "busy"); return reply;
            }
            if (current == null || !current.id.equals(id) || !active(current)) {
                final Session s = new Session(id); current = s;
                remote.check((success, message) -> {
                    synchronized (FireTvSetupProvisioning.class) {
                        if (!active(s)) return;
                        if (success) { s.state = "ready"; return; }
                        if (remote.paired()) { s.state = "failed"; return; }
                        remote.beginPairing((ok, ignored) -> state(s, ok ? "pin-ready" : "failed"));
                    }
                });
            }
        } else if ("fire-tv-cancel".equals(method)) {
            if (current != null && current.id.equals(id)) {
                current.state = "cancelled"; remote.cancelPairing();
            }
        } else if (!"fire-tv-status".equals(method)) throw new IllegalArgumentException("Unsupported setup operation");
        reply.putString("status", current == null || !current.id.equals(id) ? "unknown" :
            !active(current) ? "expired" : current.state);
        return reply;
    }

    /** content write streams stdin into this pipe. No secret is put in an intent or argv. */
    public static synchronized ParcelFileDescriptor openPin(Context context, String id, String mode) throws IOException {
        if (!FireTvNativeRemote.isTarget() || !"w".equals(mode) || !validId(id) ||
                current == null || !current.id.equals(id) || !active(current) || !"pin-ready".equals(current.state)) {
            throw new IOException("No pending setup request");
        }
        final Session s = current;
        final ParcelFileDescriptor[] pipe = ParcelFileDescriptor.createPipe();
        s.state = "verifying";
        Thread reader = new Thread(() -> {
            try (ParcelFileDescriptor input = pipe[0]; ByteArrayOutputStream bytes = new ByteArrayOutputStream()) {
                long deadline = SystemClock.elapsedRealtime() + 5000;
                StructPollfd poll = new StructPollfd(); poll.fd = input.getFileDescriptor();
                poll.events = (short) (OsConstants.POLLIN | OsConstants.POLLHUP);
                byte[] buffer = new byte[6];
                while (true) {
                    int remaining = (int) (deadline - SystemClock.elapsedRealtime());
                    if (remaining <= 0 || Os.poll(new StructPollfd[]{poll}, remaining) == 0) throw new IOException("Setup stream timeout");
                    int n = Os.read(input.getFileDescriptor(), buffer, 0, buffer.length);
                    if (n == 0) break;
                    if (bytes.size() + n > 5) throw new IOException("Invalid setup input");
                    bytes.write(buffer, 0, n);
                }
                String pin = new String(bytes.toByteArray(), StandardCharsets.US_ASCII);
                if (!pin.matches("[0-9]{4}\\n?")) throw new IOException("Invalid setup input");
                synchronized (FireTvSetupProvisioning.class) {
                    if (!active(s) || !"verifying".equals(s.state)) return;
                    FireTvNativeRemote.get(context).finishPairing(pin.trim(), (ok, ignored) -> state(s, ok ? "ready" : "failed"));
                }
            } catch (Exception ignored) { state(s, "failed"); }
        }, "AZSign-PIN-Setup");
        reader.setDaemon(true); reader.start();
        return pipe[1];
    }
}
