package br.com.azsign.gestureprobe;
import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.widget.Button;
import android.widget.LinearLayout;
public class ProbeActivity extends Activity {
    static int clicks;
    static ProbeActivity current;
    static android.app.AlertDialog dialog;
    static int dialogClicks;
    static void showDialog() {
        dialog=new android.app.AlertDialog.Builder(current).setTitle("Teste de janela modal")
            .setMessage("O botão atrás desta janela não deve receber cliques.")
            .setPositiveButton("Fechar diagnóstico",(d,w) -> { dialogClicks++; Log.i("AZSignProbe","DIALOG clicked"); })
            .create();
        dialog.setCanceledOnTouchOutside(false);
        dialog.show();
    }
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        current=this;
        clicks=0;
        dialogClicks=0;
        LinearLayout layout=new LinearLayout(this);
        layout.setOrientation(LinearLayout.HORIZONTAL);
        Button enabled=new Button(this);
        enabled.setText("Clique permitido");
        enabled.setOnClickListener(v -> { clicks++; Log.i("AZSignProbe", "CLICK count="+clicks); });
        Button disabled=new Button(this);
        disabled.setText("Não deve clicar");
        disabled.setEnabled(false);
        layout.addView(enabled,new LinearLayout.LayoutParams(0,-1,1));
        layout.addView(disabled,new LinearLayout.LayoutParams(0,-1,1));
        setContentView(layout);
    }
}
