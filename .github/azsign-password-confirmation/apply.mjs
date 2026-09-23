// Apply AFTER the existing universal-v13 hardware patches, BEFORE bridge generation/build.
// Strict anchors: stop rather than silently producing an APK without confirmation.
import { readFileSync, writeFileSync, copyFileSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(process.argv[2] ?? '.')
function patch(file, old, replacement) {
  const path = resolve(root, file)
  const source = readFileSync(path, 'utf8')
  if (source.split(old).length !== 2) throw new Error(`Expected one anchor: ${file}`)
  writeFileSync(path, source.replace(old, () => replacement))
}
const android = 'flutter/android/app/src/main'
copyFileSync(resolve(dirname(fileURLToPath(import.meta.url)), 'AzsignProvisioningProvider.java'),
  resolve(root, android, 'kotlin/com/carriez/flutter_hbb/AzsignProvisioningProvider.java'))
patch(`${android}/AndroidManifest.xml`, '</application>', `
        <provider android:name=".AzsignProvisioningProvider"
            android:authorities="com.carriez.flutter_hbb.azsign.provisioning"
            android:exported="true" android:grantUriPermissions="false" />
    </application>`)
patch(`${android}/kotlin/com/carriez/flutter_hbb/MainActivity.kt`, '            when (call.method) {', `            when (call.method) {
                "azsign_password_result" -> {
                    val id = call.argument<String>("request_id")
                    val persisted = call.argument<Boolean>("persisted") == true
                    result.success(AzsignProvisioningProvider.record(applicationContext, id, persisted))
                }`)

patch('libs/hbb_common/src/config/permanent_password.rs', '#[cfg(test)]\nfn local_permanent_password_storage_matches_plain(', '#[cfg(any(test, target_os = "android"))]\npub(super) fn local_permanent_password_storage_matches_plain(')
patch('libs/hbb_common/src/config.rs', '    pub fn set_permanent_password(password: &str) -> bool {', `    /// AZSign Android: a successful setter alone does not prove disk persistence.
    #[cfg(target_os = "android")]
    pub fn azsign_set_password_verified(password: &str) -> bool {
        if password.is_empty() || !Self::set_permanent_password(password) { return false; }
        let persisted: Config = match confy::load_path(Self::file()) {
            Ok(value) => value,
            Err(_) => return false,
        };
        permanent_password::local_permanent_password_storage_matches_plain(&persisted.password, &persisted.salt, password)
    }

    pub fn set_permanent_password(password: &str) -> bool {`)
patch('src/ui_interface.rs', '        return config::Config::set_permanent_password(&password);', `        #[cfg(target_os = "android")]
        return config::Config::azsign_set_password_verified(&password);
        #[cfg(target_os = "ios")]
        return config::Config::set_permanent_password(&password);`)

patch('flutter/lib/common.dart', '    print("initialLink: $initialLink");', '    // Do not log deep links: provisioning URIs may contain credentials.')
patch('flutter/lib/common.dart', '    debugPrint("A uri was received: $uri. handleByFlutter $handleByFlutter");', '    // Do not log credential-bearing URIs.')
patch('flutter/lib/common.dart', '      final password = uri.path.substring("/".length);', `      final requestId = uri.queryParameters['azsign_request'];
      final password = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;`)
patch('flutter/lib/common.dart', "          showToast(translate(ok ? 'Successful' : 'Failed'));", `          if (isAndroid && requestId != null && RegExp(r'^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$').hasMatch(requestId)) {
            try {
              await platformFFI.invokeMethod('azsign_password_result', {
                'request_id': requestId, 'persisted': ok,
              });
            } catch (_) {
              // No receipt means unconfirmed; never report success to Setup via logs.
              debugPrint('AZSign: could not publish provisioning receipt');
            }
          }
          showToast(translate(ok ? 'Successful' : 'Failed'));`)
console.log('Password confirmation v1 applied; build and hardware validation still required.')
