package com.carriez.flutter_hbb;

import android.app.Activity;
import android.app.AlertDialog;
import android.os.Bundle;
import android.text.InputFilter;
import android.text.InputType;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/** Local, non-exported configuration; no remote intent accepts a PIN or token. */
public final class FireTvPairingActivity extends Activity {
    private FireTvNativeRemote remote;
    private TextView status;
    private EditText pin;
    private Button request, confirm, check, forget;
    private boolean busy;
    private int dp(int value) { return (int) (value * getResources().getDisplayMetrics().density); }
    private TextView text(LinearLayout layout, String value, int size) {
        TextView view = new TextView(this); view.setText(value); view.setTextSize(size); view.setPadding(0, dp(8), 0, dp(12)); layout.addView(view); return view;
    }
    private Button button(LinearLayout layout, String value) {
        Button button = new Button(this); button.setText(value); button.setMinHeight(dp(48)); layout.addView(button); return button;
    }
    @Override public void onCreate(Bundle saved) {
        setTheme(android.R.style.Theme_DeviceDefault_Light_NoActionBar); super.onCreate(saved);
        if (!FireTvNativeRemote.isTarget()) { finish(); return; }
        remote = FireTvNativeRemote.get(this);
        ScrollView scroll = new ScrollView(this); LinearLayout layout = new LinearLayout(this); layout.setOrientation(LinearLayout.VERTICAL); layout.setPadding(dp(28),dp(20),dp(28),dp(20)); scroll.addView(layout); setContentView(scroll);
        text(layout, "Controle desta Fire TV", 26);
        text(layout, "Configure uma vez para permitir a navegação pelo AZSign Remote. O controle físico continua funcionando normalmente.", 18);
        status = text(layout, remote.message(), 18); status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        request = button(layout, "1. Mostrar PIN da Fire TV");
        text(layout, "Anote os quatro números da janela da Fire TV. Pressione Voltar para fechar a janela e digite o código abaixo.", 17);
        pin = new EditText(this); pin.setHint("PIN de quatro dígitos"); pin.setSingleLine(true); pin.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_VARIATION_PASSWORD); pin.setFilters(new InputFilter[]{new InputFilter.LengthFilter(4)}); pin.setImeOptions(EditorInfo.IME_ACTION_DONE); layout.addView(pin);
        confirm = button(layout, "2. Confirmar pareamento");
        check = button(layout, "Verificar conexão");
        forget = button(layout, "Esquecer pareamento deste aplicativo");
        Button close = button(layout, "Voltar ao AZSign Remote"); close.setOnClickListener(v -> finish());
        request.setOnClickListener(v -> { setBusy(true); remote.beginPairing(callback(pin)); });
        confirm.setOnClickListener(v -> { String value = pin.getText().toString(); pin.setText(""); setBusy(true); remote.finishPairing(value, callback(check)); });
        pin.setOnEditorActionListener((view, action, event) -> { if (action == EditorInfo.IME_ACTION_DONE && !busy) { confirm.performClick(); return true; } return false; });
        check.setOnClickListener(v -> { setBusy(true); remote.check(callback(check)); });
        forget.setOnClickListener(v -> new AlertDialog.Builder(this).setTitle("Esquecer o pareamento?")
            .setMessage("O AZSign Remote precisará de um novo PIN para controlar esta Fire TV. O controle físico não será removido.")
            .setNegativeButton("Cancelar", null).setPositiveButton("Esquecer", (dialog, which) -> { setBusy(true); remote.forget(callback(request)); }).show());
        request.requestFocus();
        setBusy(true); remote.check(callback(request));
    }
    @Override public void onDestroy() {
        if (remote != null && !isChangingConfigurations()) remote.cancelPairing();
        super.onDestroy();
    }
    private FireTvNativeRemote.Callback callback(View nextFocus) {
        return (success, message) -> runOnUiThread(() -> {
            if (!isFinishing() && !isDestroyed()) {
                setBusy(false); status.setText(message);
                // Disabling a focused TV button moves focus to Close. Restore an
                // intentional target when asynchronous work finishes.
                (success ? nextFocus : request).requestFocus();
            }
        });
    }
    private void setBusy(boolean value) { busy = value; request.setEnabled(!value); confirm.setEnabled(!value); check.setEnabled(!value); forget.setEnabled(!value); pin.setEnabled(!value); }
}
