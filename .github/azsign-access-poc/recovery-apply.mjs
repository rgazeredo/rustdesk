// Applied only to the pinned Android distribution, after access/password patches.
import {readFileSync, writeFileSync, copyFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
const root=resolve(process.argv[2]??'.');
const origin=process.env.AZSIGN_RECOVERY_ORIGIN??'';
if (origin && !/^https:\/\/[a-z0-9]+([.-][a-z0-9]+)*$/.test(origin)) throw new Error('Invalid recovery origin');
function patch(file, before, after) {
 const path=join(root,file), text=readFileSync(path,'utf8');
 if(text.split(before).length!==2) throw new Error(`Unexpected anchor: ${file}`);
 writeFileSync(path,text.replace(before,()=>after));
}
const java='flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/';
for(const file of ['AzsignRecovery.java','AzsignRecoveryAndroid.java']) copyFileSync(join(import.meta.dirname,file),join(root,java,file));
patch(java+'MainApplication.kt','AzsignRenewalRuntime.start(filesDir)',`AzsignRenewalRuntime.start(filesDir)\n        AzsignRecoveryAndroid.start(applicationContext, ${JSON.stringify(origin)})`);
patch(java+'MainActivity.kt','            when (call.method) {',`            when (call.method) {
                "azsign_device_status" -> {
                    try { result.success(AzsignRecoveryAndroid.status(applicationContext)) }
                    catch (_: Exception) { result.error("status_unavailable", "Estado indisponível", null) }
                }
`);
copyFileSync(join(import.meta.dirname,'recovery-native.rs'),join(root,'src/azsign_recovery_native.rs'));
patch('src/lib.rs','pub mod flutter_ffi;', 'pub mod flutter_ffi;\n#[cfg(target_os = "android")]\nmod azsign_recovery_native;');
copyFileSync(join(import.meta.dirname,'device_page.dart'),join(root,'flutter/lib/mobile/pages/azsign_device_page.dart'));
patch('flutter/lib/mobile/pages/home_page.dart',"import 'connection_page.dart';", "import 'connection_page.dart';\nimport 'azsign_device_page.dart';");
patch('flutter/lib/mobile/pages/home_page.dart','    return WillPopScope(', '    if (isAndroid) return const AzsignDevicePage();\n    return WillPopScope(');
copyFileSync(join(import.meta.dirname,'azsign-remote.svg'),join(root,'flutter/assets/azsign-remote.svg'));
const strings=join(root,'flutter/android/app/src/main/res/values/strings.xml');
let s=readFileSync(strings,'utf8');
s=s.replace(/(<string name="app_name">)[^<]+/, '$1AZSign Remote').replace('when RustDesk screen sharing', 'when AZSign Remote screen sharing');writeFileSync(strings,s);
const manifest=join(root,'flutter/android/app/src/main/AndroidManifest.xml');
s=readFileSync(manifest,'utf8').replace('android:label="RustDesk"','android:label="AZSign Remote"').replace('android:label="RustDesk Input"','android:label="AZSign Remote Input"');writeFileSync(manifest,s);
console.log('AZSign Android identity, recovery and read-only device screen applied.');

patch(java+'MainService.kt', 'const val DEFAULT_NOTIFY_TITLE = "RustDesk"', 'const val DEFAULT_NOTIFY_TITLE = "AZSign Remote"');
patch(java+'MainService.kt', 'val channelName = "RustDesk Service"', 'val channelName = "AZSign Remote"');
patch(java+'MainService.kt', 'description = "RustDesk Service Channel"', 'description = "Compartilhamento de tela AZSign Remote"');

// Use the existing fixed-setting mechanism so old saved preferences cannot re-enable it.
patch('libs/hbb_common/src/config.rs',
 'pub static ref OVERWRITE_LOCAL_SETTINGS: RwLock<HashMap<String, String>> = Default::default();',
 `pub static ref OVERWRITE_LOCAL_SETTINGS: RwLock<HashMap<String, String>> = {
        let mut settings = HashMap::new();
        #[cfg(target_os = "android")]
        settings.insert("disable-floating-window".to_owned(), "Y".to_owned());
        RwLock::new(settings)
    };`);
patch('flutter/android/app/src/main/AndroidManifest.xml',
 'android:name=".FloatingWindowService"\n            android:enabled="true"',
 'android:name=".FloatingWindowService"\n            android:enabled="false"');
