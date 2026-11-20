package com.carriez.flutter_hbb;

import android.content.Context;
import android.os.Build;
import android.os.SystemClock;
import android.util.Log;
import android.view.KeyEvent;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import org.json.JSONObject;

/** Native Fire TV input backend; no ADB client, shell commands or off-device server. */
public final class FireTvNativeRemote {
    public interface Callback { void done(boolean success, String message); }
    private static FireTvNativeRemote instance;
    private final FireTvCredentialStore store;
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(1, 1, 0, TimeUnit.MILLISECONDS,
        new ArrayBlockingQueue<>(32), runnable -> { Thread t = new Thread(runnable, "AZSign-FireTV"); t.setDaemon(true); return t; });
    private volatile boolean ready;
    private volatile String message = "Verificando controle desta Fire TV";
    private volatile Session session;
    private byte[] pendingCertificate;
    private long pendingUntil;
    private boolean activated;
    private final java.util.concurrent.atomic.AtomicInteger inputEpoch = new java.util.concurrent.atomic.AtomicInteger();
    private static final class Session {
        final byte[] certificate; final String token; final FireTvTransport transport;
        Session(byte[] certificate, String token) { this.certificate = certificate.clone(); this.token = token; this.transport = new FireTvTransport(certificate); }
    }
    public static boolean isTarget() {
        return FireTvInputPolicy.supported(Build.MANUFACTURER, Build.MODEL, Build.VERSION.SDK_INT);
    }
    public static synchronized FireTvNativeRemote get(Context context) {
        if (!isTarget()) throw new IllegalStateException("Unsupported device");
        if (instance == null) instance = new FireTvNativeRemote(context.getApplicationContext());
        return instance;
    }
    private FireTvNativeRemote(Context context) {
        store = new FireTvCredentialStore(context);
        submit(() -> {
            try {
                String token = store.token(); byte[] certificate = store.certificate();
                if (token != null && certificate != null) session = new Session(certificate, token);
                else message = "Configure o controle desta Fire TV";
            } catch (Exception error) { fail(error, false); }
        }, null);
    }
    public static String status(Context context) {
        try {
            JSONObject result = new JSONObject().put("supported", isTarget());
            if (isTarget()) {
                FireTvNativeRemote remote = get(context);
                result.put("paired", remote.session != null).put("ready", remote.ready).put("message", remote.message);
            }
            return result.toString();
        } catch (Exception error) { return "{\"supported\":false}"; }
    }
    public static void warmup(Context context) { if (isTarget()) get(context).check(null); }
    public boolean paired() { return session != null; }
    public String message() { return message; }

    private void submit(Runnable task, Callback callback) {
        try { worker.execute(task); }
        catch (java.util.concurrent.RejectedExecutionException error) {
            if (callback != null) callback.done(false, "Aguarde os comandos em andamento");
            Log.w("AZSignFireNative", "Input queue full; operation refused");
        }
    }
    private void ensureService() throws Exception {
        if (!activated) { FireTvTransport.activate(); activated = true; }
    }
    private void checkNow() throws Exception {
        if (session == null) throw new IllegalStateException("Pairing required");
        ensureService();
        JSONObject status;
        long deadline = SystemClock.elapsedRealtime() + 4000;
        while (true) {
            try { status = new JSONObject(session.transport.request("/v1/FireTV/status", null, session.token)); break; }
            catch (java.net.ConnectException error) {
                if (SystemClock.elapsedRealtime() >= deadline) throw error;
                Thread.sleep(250);
            }
        }
        for (String field : new String[]{"osVersion", "platformType", "turnstileVersion"}) {
            if (!(status.opt(field) instanceof String)) throw new IllegalStateException("Invalid native status");
        }
        ready = true; message = "Controle desta Fire TV ativo";
    }
    public void check(Callback callback) {
        submit(() -> {
            try {
                if (session == null) { ready = false; message = "Configure o controle desta Fire TV"; }
                else checkNow();
                if (callback != null) callback.done(ready, message);
            } catch (Exception error) { fail(error, true); if (callback != null) callback.done(false, message); }
        }, callback);
    }
    public void beginPairing(Callback callback) {
        submit(() -> {
            inputEpoch.incrementAndGet(); ready = false; pendingCertificate = null; pendingUntil = 0;
            try {
                ensureService();
                byte[] certificate = store.certificate();
                if (certificate == null) {
                    long deadline = SystemClock.elapsedRealtime() + 6000;
                    while (true) {
                        try { certificate = FireTvTransport.discoverCertificate(); break; }
                        catch (java.net.ConnectException error) {
                            if (SystemClock.elapsedRealtime() >= deadline) throw error;
                            Thread.sleep(250);
                        }
                    }
                }
                FireTvTransport transport = new FireTvTransport(certificate);
                JSONObject response = new JSONObject(transport.request("/v1/FireTV/pin/display", new JSONObject().put("friendlyName", "AZSign Remote").toString(), null));
                if (!"OK".equals(response.optString("description"))) throw new IllegalStateException("PIN display refused");
                pendingCertificate = certificate.clone(); pendingUntil = SystemClock.elapsedRealtime() + 120000;
                message = "Anote o PIN da Fire TV, pressione Voltar e digite o código abaixo";
                callback.done(true, message);
            } catch (Exception error) { fail(error, false); callback.done(false, message); }
        }, callback);
    }
    public void finishPairing(String pin, Callback callback) {
        if (pin == null || !pin.matches("[0-9]{4}")) { callback.done(false, "Digite os quatro números mostrados na TV"); return; }
        submit(() -> {
            try {
                if (pendingCertificate == null || SystemClock.elapsedRealtime() > pendingUntil) throw new IllegalStateException("PIN request expired");
                byte[] certificate = pendingCertificate.clone();
                FireTvTransport transport = new FireTvTransport(certificate);
                JSONObject response = new JSONObject(transport.request("/v1/FireTV/pin/verify", new JSONObject().put("pin", pin).toString(), null));
                String token = response.optString("description", "");
                if (token.isEmpty() || token.length() > 4096 || !token.matches("[\\x20-\\x7e]+")) {
                    callback.done(false, "PIN não aceito. Confira o código ou solicite outro"); return;
                }
                Session next = new Session(certificate, token);
                JSONObject status = new JSONObject(next.transport.request("/v1/FireTV/status", null, token));
                for (String field : new String[]{"osVersion", "platformType", "turnstileVersion"}) {
                    if (!(status.opt(field) instanceof String)) throw new IllegalStateException("Invalid native status");
                }
                store.save(certificate, token);
                if (!token.equals(store.token()) || !java.security.MessageDigest.isEqual(certificate, store.certificate())) throw new java.security.GeneralSecurityException("Credential readback failed");
                session = next; pendingCertificate = null; pendingUntil = 0;
                ready = true; message = "Controle desta Fire TV ativo";
                callback.done(true, message);
            } catch (Exception error) { fail(error, false); callback.done(false, message); }
        }, callback);
    }
    public void forget(Callback callback) {
        submit(() -> {
            try { inputEpoch.incrementAndGet(); store.clear(); session = null; ready = false; pendingCertificate = null; pendingUntil = 0; activated = false;
                message = "Pareamento removido deste aplicativo"; callback.done(true, message);
            } catch (Exception error) { fail(error, false); callback.done(false, message); }
        }, callback);
    }
    public void cancelPairing() {
        submit(() -> {
            inputEpoch.incrementAndGet(); pendingCertificate = null; pendingUntil = 0;
            if (session != null) { try { checkNow(); } catch (Exception error) { fail(error, true); } }
        }, null);
    }
    public static void cancelInput(Context context) { if (isTarget()) get(context).inputEpoch.incrementAndGet(); }
    public void press(String action) {
        if (!action.matches("dpad_up|dpad_down|dpad_left|dpad_right|select|home|back")) return;
        final int epoch = inputEpoch.get();
        submit(() -> {
            try {
                if (epoch != inputEpoch.get()) return;
                if (pendingCertificate != null && SystemClock.elapsedRealtime() > pendingUntil) { pendingCertificate = null; pendingUntil = 0; }
                if (session == null || pendingCertificate != null) { message = "Conclua o pareamento desta Fire TV"; return; }
                if (!ready) checkNow();
                Session current = session;
                if (current == null) return;
                current.transport.press(action, current.token);
                Log.i("AZSignFireNative", "Native navigation completed");
            } catch (Exception error) { fail(error, true); }
        }, null);
    }
    public static boolean handleKey(Context context, KeyEvent event) {
        if (!isTarget() || event.isAltPressed() || event.isCtrlPressed() || event.isMetaPressed() || event.isShiftPressed()) return false;
        String action = FireTvInputPolicy.navigation(event.getKeyCode());
        if (action == null) return false;
        if (event.getAction() == KeyEvent.ACTION_DOWN) get(context).press(action);
        return true;
    }
    private void fail(Exception error, boolean authenticated) {
        inputEpoch.incrementAndGet(); ready = false;
        if (authenticated && error instanceof FireTvTransport.HttpFailure && (((FireTvTransport.HttpFailure) error).status == 401 || ((FireTvTransport.HttpFailure) error).status == 403)) {
            store.invalidateToken(); session = null; message = "Autorize novamente o controle desta Fire TV";
        } else if (error instanceof javax.net.ssl.SSLException || error instanceof java.security.GeneralSecurityException) {
            message = "Não foi possível confirmar a identidade da Fire TV. Confira a data ou refaça o pareamento";
        } else if (error instanceof IllegalStateException) message = "Solicite o PIN e conclua o pareamento desta Fire TV";
        else { activated = false; message = "Não foi possível conectar ao controle da Fire TV. Tente novamente"; }
        Log.w("AZSignFireNative", "Native input unavailable: " + error.getClass().getSimpleName());
    }
}
