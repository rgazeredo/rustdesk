package br.com.azsign.gestureprobe;
import android.accessibilityservice.AccessibilityService;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.accessibility.AccessibilityEvent;
import com.carriez.flutter_hbb.AquarioNodeClick;
public class ProbeService extends AccessibilityService {
    final Handler handler=new Handler(Looper.getMainLooper());
    AquarioNodeClick input;
    private void later(Runnable action, long delay) {
        handler.postDelayed(() -> {
            android.view.accessibility.AccessibilityNodeInfo root=getRootInActiveWindow();
            if(root==null) { Log.i("AZSignProbe","FAIL no diagnostic window"); return; }
            try {
                if(!"br.com.azsign.gestureprobe".contentEquals(root.getPackageName()==null ? "" : root.getPackageName())) {
                    Log.i("AZSignProbe","FAIL diagnostic window not focused; skipped"); return;
                }
            } finally { root.recycle(); }
            action.run();
        },delay);
    }
    private void check(String name,int expected) {
        Log.i("AZSignProbe", (ProbeActivity.clicks==expected ? "PASS " : "FAIL ")+name+" actual="+ProbeActivity.clicks+" expected="+expected);
    }
    @Override protected void onServiceConnected() {
        input=new AquarioNodeClick(this);
        later(() -> { input.mouse(0,400,300); input.mouse(9,400,300); input.mouse(10,400,300); },3000);
        later(() -> check("left click",1),3500);
        later(() -> { input.mouse(9,400,300); input.mouse(8,700,300); input.mouse(10,700,300); },4000);
        later(() -> check("drag does not click",1),4500);
        later(() -> { input.mouse(10,400,300); },5000);
        later(() -> check("orphan up does not click",1),5500);
        later(() -> { input.mouse(9,1400,300); input.mouse(10,1400,300); },6000);
        later(() -> check("disabled button does not click",1),6500);
        later(() -> { input.mouse(9,3000,300); input.mouse(10,3000,300); },7000);
        later(() -> check("outside screen does not click",1),7500);
        later(() -> { input.touch(4,200,150,2); input.touch(6,0,0,2); },8000);
        later(() -> check("scaled stationary touch",2),8500);
        later(() -> { input.touch(4,200,150,2); input.touch(5,50,0,2); input.touch(6,0,0,2); },9000);
        later(() -> check("touch pan does not click",2),9500);
        later(() -> input.mouse(9,400,300),10000);
        later(() -> input.mouse(10,400,300),10800);
        later(() -> check("long press does not click",2),11300);
        later(() -> { input.mouse(9,400,300); input.mouse(10,400,300); input.close(); },12000);
        later(() -> check("service close cancels queued click",2),12500);
        later(() -> ProbeActivity.showDialog(),14000);
        later(() -> { input.mouse(9,100,100); input.mouse(10,100,100); },15000);
        later(() -> check("modal prevents click through",2),15500);
        later(() -> {
            android.widget.Button b=ProbeActivity.dialog.getButton(-1);
            int[] point=new int[2]; b.getLocationOnScreen(point);
            int x=point[0]+b.getWidth()/2,y=point[1]+b.getHeight()/2;
            input.mouse(9,x,y); input.mouse(10,x,y);
        },16000);
        later(() -> Log.i("AZSignProbe",(ProbeActivity.dialogClicks==1 ? "PASS " : "FAIL ")+"dialog target count="+ProbeActivity.dialogClicks),16500);
    }
    @Override public void onAccessibilityEvent(AccessibilityEvent e) {}
    @Override public void onInterrupt() {}
}
