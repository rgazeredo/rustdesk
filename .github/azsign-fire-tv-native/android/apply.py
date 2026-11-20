"""Apply after existing AZSign recovery, D-pad and Fire TV event patches."""
from pathlib import Path
import shutil
import sys

root = Path(sys.argv[1])
support = Path(__file__).resolve().parent
android = root / 'flutter/android/app/src/main'
base = android / 'kotlin/com/carriez/flutter_hbb'
changes = {}

def replace(file, before, after):
    path = root / file
    text = changes.get(path, path.read_text())
    if text.count(before) != 1:
        raise SystemExit('Native Fire TV patch anchor mismatch: ' + str(file))
    changes[path] = text.replace(before, after)

native = 'flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/'
replace(native + 'InputService.kt',
    '                    if (FireTvNodeClick.isTarget()) rootInActiveWindow?.refresh()',
    '                    if (FireTvNativeRemote.handleKey(this@InputService, event)) return@post\n                    if (FireTvNodeClick.isTarget()) rootInActiveWindow?.refresh()')
replace(native + 'InputService.kt', '        setServiceInfo(info)',
    '        setServiceInfo(info)\n        FireTvNativeRemote.warmup(applicationContext)')
replace(native + 'InputService.kt', '        Log.d(logTag, "onKeyEvent $keyEvent textToCommit:$textToCommit")',
    '        // Never log typed text, pairing PINs or remote passwords.\n        Log.d(logTag, "Remote keyboard event received")')
replace(native + 'MainActivity.kt', '            when (call.method) {', '''            when (call.method) {
                "azsign_fire_tv_status" -> result.success(FireTvNativeRemote.status(applicationContext))
                "azsign_fire_tv_settings" -> {
                    if (FireTvNativeRemote.isTarget()) {
                        startActivity(android.content.Intent(this, FireTvPairingActivity::class.java))
                        result.success(true)
                    } else result.success(false)
                }''')
manifest = 'flutter/android/app/src/main/AndroidManifest.xml'
text = (root / manifest).read_text()
if 'networkSecurityConfig' in text or 'FireTvPairingActivity' in text:
    raise SystemExit('Unexpected existing native security config/activity')
replace(manifest, '<application', '<application android:networkSecurityConfig="@xml/fire_tv_network_security"')
replace(manifest, '</application>', '''    <activity android:name=".FireTvPairingActivity" android:exported="false"
            android:theme="@android:style/Theme.DeviceDefault.Light.NoActionBar" />
    </application>''')
replace(native + 'AzsignProvisioningProvider.java', '        if ("/device-id".equals(uri.getPath())) {', '''        if ("/fire-tv-input".equals(uri.getPath())) {
            MatrixCursor cursor = new MatrixCursor(new String[]{"protocol", "supported", "paired", "ready"});
            try {
                org.json.JSONObject state = new org.json.JSONObject(FireTvNativeRemote.status(getContext()));
                cursor.addRow(new Object[]{1, state.optBoolean("supported") ? 1 : 0, state.optBoolean("paired") ? 1 : 0, state.optBoolean("ready") ? 1 : 0});
            } catch (Exception error) { cursor.addRow(new Object[]{1, 0, 0, 0}); }
            return cursor;
        }
        if ("/device-id".equals(uri.getPath())) {''')
replace(native + 'AzsignProvisioningProvider.java', 'new String[]{"protocol", "device_id"}', 'new String[]{"protocol", "device_id", "fire_tv_setup"}')
replace(native + 'AzsignProvisioningProvider.java', 'new Object[]{1, 1}', 'new Object[]{1, 1, 1}')
replace(native + 'AzsignProvisioningProvider.java', '    @Override public String getType(Uri uri)', """    private void requireSetupCaller() {
        int uid = Binder.getCallingUid();
        if (uid != 2000 && uid != 0 && uid != Process.myUid()) throw new SecurityException("ADB only");
    }
    @Override public android.os.Bundle call(String method, String arg, android.os.Bundle extras) {
        requireSetupCaller();
        return FireTvSetupProvisioning.call(getContext(), method, arg);
    }
    @Override public android.os.ParcelFileDescriptor openFile(Uri uri, String mode) throws java.io.FileNotFoundException {
        requireSetupCaller();
        if (uri.getPathSegments().size() != 2 || !"fire-tv-pin".equals(uri.getPathSegments().get(0))) throw new java.io.FileNotFoundException("Unsupported setup input");
        try { return FireTvSetupProvisioning.openPin(getContext(), uri.getLastPathSegment(), mode); }
        catch (java.io.IOException error) { throw new java.io.FileNotFoundException("Setup input unavailable"); }
    }
    @Override public String getType(Uri uri)""")
page = 'flutter/lib/mobile/pages/azsign_device_page.dart'
replace(page, '  Map<String, dynamic> _status = {};', '  Map<String, dynamic> _status = {};\n  Map<String, dynamic> _fireTv = {};')
replace(page, "      final raw = await platformFFI.invokeMethod('azsign_device_status');", "      final raw = await platformFFI.invokeMethod('azsign_device_status');\n      final fireRaw = await platformFFI.invokeMethod('azsign_fire_tv_status');")
replace(page, '        _unavailable = false;', '        _unavailable = false;\n        _fireTv = jsonDecode(fireRaw as String) as Map<String, dynamic>;')
replace(page, "    if (model.connectStatus > 0) return 'Pronto para acesso remoto';", "    if (_fireTv['supported'] == true && _fireTv['ready'] != true) return 'Controle desta Fire TV pendente';\n    if (model.connectStatus > 0) return 'Pronto para acesso remoto';")
replace(page, '    final ready = !missingScreen && !missingInput && model.connectStatus > 0;', '    final ready = !missingScreen && !missingInput && model.connectStatus > 0 &&\n        (_fireTv[\'supported\'] != true || _fireTv[\'ready\'] == true);')
replace(page, '                    const SizedBox(height: 28),\n                    Align(', '''                    if (_fireTv['supported'] == true) ...[
                      const SizedBox(height: 20),
                      Text(_fireTv['message'] as String? ?? 'Configure o controle desta Fire TV'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () async {
                          await platformFFI.invokeMethod('azsign_fire_tv_settings');
                        },
                        icon: const Icon(Icons.settings_remote_outlined),
                        label: const Text('Configurar controle desta Fire TV'),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Align(''')
# Only write after every expected baseline anchor was validated.
for path, text in changes.items():
    path.write_text(text)
for file in support.glob('*.java'):
    shutil.copy2(file, base / file.name)
shutil.copy2(support / 'fire_tv_network_security.xml', android / 'res/xml/fire_tv_network_security.xml')
print('Native Fire TV backend and local pairing UI applied.')
