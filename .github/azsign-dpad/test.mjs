import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';
const dir = mkdtempSync(join(tmpdir(), 'azsign-dpad-unit-'));
const javaHome = process.env.JAVA_HOME ?? '/opt/homebrew/opt/openjdk@17';
const files = {
 'android/util/Log.java': 'package android.util; public class Log { public static int i(String t,String m){return 0;} }',
 'android/view/View.java': 'package android.view; public class View { public static final int FOCUS_UP=33,FOCUS_DOWN=130,FOCUS_LEFT=17,FOCUS_RIGHT=66; }',
 'android/view/KeyEvent.java': `package android.view; public class KeyEvent {
 public static final int KEYCODE_DPAD_UP=19,KEYCODE_DPAD_DOWN=20,KEYCODE_DPAD_LEFT=21,KEYCODE_DPAD_RIGHT=22,KEYCODE_ENTER=66,KEYCODE_NUMPAD_ENTER=160,KEYCODE_DPAD_CENTER=23,ACTION_DOWN=0;
 public int key,action; public boolean modified; public KeyEvent(int k,int a){key=k;action=a;}
 public int getKeyCode(){return key;} public int getAction(){return action;}
 public boolean isAltPressed(){return modified;} public boolean isCtrlPressed(){return false;} public boolean isMetaPressed(){return false;} public boolean isShiftPressed(){return false;}
 }`,
 'android/view/accessibility/AccessibilityNodeInfo.java': `package android.view.accessibility; public class AccessibilityNodeInfo {
 public static final int FOCUS_INPUT=1,ACTION_FOCUS=1,ACTION_CLICK=16;
 public boolean editable=false,visible=true,enabled=true,clickable=true; public int window=1,actions=0,last=0,direction=0;
 public AccessibilityNodeInfo focused,target;
 public AccessibilityNodeInfo findFocus(int f){return focused;} public boolean isEditable(){return editable;}
 public AccessibilityNodeInfo focusSearch(int d){direction=d;return target;}
 public boolean isVisibleToUser(){return visible;} public boolean isEnabled(){return enabled;}
 public int getWindowId(){return window;} public boolean isClickable(){return clickable;}
 public boolean performAction(int a){actions++;last=a;return true;} public void recycle(){}
 }`,
 'android/accessibilityservice/AccessibilityService.java': `package android.accessibilityservice; import android.view.accessibility.AccessibilityNodeInfo; public class AccessibilityService { public AccessibilityNodeInfo root; public AccessibilityNodeInfo getRootInActiveWindow(){return root;} }`,
 'TestDpad.java': `import android.accessibilityservice.AccessibilityService; import android.view.KeyEvent; import android.view.accessibility.AccessibilityNodeInfo; import com.carriez.flutter_hbb.AzsignDpadNavigation;
 public class TestDpad {
 static void check(boolean value){if(!value)throw new AssertionError();}
 public static void main(String[] args){
 AccessibilityService s=new AccessibilityService(); AccessibilityNodeInfo r=new AccessibilityNodeInfo(),f=new AccessibilityNodeInfo(),t=new AccessibilityNodeInfo();s.root=r;r.focused=f;f.target=t;
 check(AzsignDpadNavigation.handle(s,new KeyEvent(20,0)));check(t.actions==1 && t.last==1 && f.direction==130);
 check(AzsignDpadNavigation.handle(s,new KeyEvent(20,1)));check(t.actions==1);
 check(AzsignDpadNavigation.handle(s,new KeyEvent(66,0)));check(f.actions==1 && f.last==16);
 check(AzsignDpadNavigation.handle(s,new KeyEvent(66,1)));check(f.actions==1);
 f.editable=true;check(!AzsignDpadNavigation.handle(s,new KeyEvent(20,0)));check(!AzsignDpadNavigation.handle(s,new KeyEvent(66,0)));f.editable=false;
 KeyEvent mod=new KeyEvent(20,0);mod.modified=true;check(!AzsignDpadNavigation.handle(s,mod));
 check(!AzsignDpadNavigation.handle(s,new KeyEvent(29,0)));
 t.enabled=false;AzsignDpadNavigation.handle(s,new KeyEvent(20,0));check(t.actions==1);t.enabled=true;
 t.window=2;AzsignDpadNavigation.handle(s,new KeyEvent(20,0));check(t.actions==1);t.window=1;
 t.visible=false;AzsignDpadNavigation.handle(s,new KeyEvent(20,0));check(t.actions==1);
 f.clickable=false;AzsignDpadNavigation.handle(s,new KeyEvent(66,0));check(f.actions==1);
 f.target=null;check(AzsignDpadNavigation.handle(s,new KeyEvent(20,0)));
 r.focused=null;r.target=null;check(AzsignDpadNavigation.handle(s,new KeyEvent(20,0)));
 s.root=null;check(!AzsignDpadNavigation.handle(s,new KeyEvent(20,0)));
 System.out.println("D-pad behavior checks passed");
 }}`
};
try {
 for (const [file, source] of Object.entries(files)) { const path=join(dir,file); mkdirSync(join(path,'..'),{recursive:true});writeFileSync(path,source); }
 const helper = join(import.meta.dirname,'AzsignDpadNavigation.java');
 execFileSync(join(javaHome,'bin/javac'),['-d',dir,...Object.keys(files).map(f=>join(dir,f)),helper]);
 console.log(execFileSync(join(javaHome,'bin/java'),['-cp',dir,'TestDpad'],{encoding:'utf8'}).trim());
 const base=join(dir,'flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb');mkdirSync(base,{recursive:true});
 writeFileSync(join(base,'InputService.kt'),'                    val possibleNodes = possibleAccessibiltyNodes()');
 execFileSync(process.execPath,[join(import.meta.dirname,'apply.mjs'),dir]);
 assert.match(readFileSync(join(base,'InputService.kt'),'utf8'),/return@post/);
 assert.throws(()=>execFileSync(process.execPath,[join(import.meta.dirname,'apply.mjs'),dir],{stdio:'pipe'}));
 console.log('Strict patch checks passed');
} finally { rmSync(dir,{recursive:true,force:true}); }
