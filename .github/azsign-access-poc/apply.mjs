import { readFileSync, writeFileSync, copyFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
const root = resolve(process.argv[2] ?? '.');
function patch(file, old, value) {
  const path = join(root, file);
  const source = readFileSync(path, 'utf8').replaceAll('\r\n', '\n');
  if (source.includes(value)) return;
  if (source.split(old).length !== 2) throw new Error(`Unexpected patch target: ${file}`);
  writeFileSync(path, source.replace(old, () => value));
}
patch('src/core_main.rs', '    let mut args = Vec::new();', '    #[cfg(all(any(target_os = "macos", target_os = "windows"), feature = "azsign-access-poc"))]\n    config::HARD_SETTINGS.write().ok()?.insert("conn-type".to_owned(), "outgoing".to_owned());\n    let mut args = Vec::new();');
patch('libs/hbb_common/Cargo.toml', 'default = []', 'default = []\nazsign-access-poc = []');
if (!readFileSync(join(root, 'libs/hbb_common/Cargo.toml'), 'utf8').includes('security-framework = "=2.10.0"'))
patch('libs/hbb_common/Cargo.toml', '\n[dependencies]\n', '\n[target.\'cfg(target_os = "macos")\'.dependencies]\nsecurity-framework = "=2.10.0"\n\n[dependencies]\n');
patch('Cargo.toml', '[features]', '[features]\nazsign-access-poc = ["hbb_common/azsign-access-poc"]');
patch('src/lib.rs', 'mod keyboard;', 'mod keyboard;\n#[cfg(all(any(target_os = "macos", target_os = "windows"), feature = "azsign-access-poc"))]\n#[no_mangle]\npub extern "C" fn azsign_native_access_enabled() -> i32 { 1 }');
patch('src/lib.rs', 'mod port_forward_mux;', 'mod port_forward_mux;\n#[cfg(all(target_os = "macos", feature = "azsign-access-poc", feature = "flutter"))]\n#[no_mangle]\npub extern "C" fn azsign_native_access_logout() { crate::flutter::sessions::close_all_sessions(); }');
patch('src/flutter.rs', '    #[cfg(any(target_os = "android", target_os = "ios"))]\n    pub fn close_all_sessions()', '    #[cfg(any(target_os = "android", target_os = "ios", all(any(target_os = "macos", target_os = "windows"), feature = "azsign-access-poc")))]\n    pub fn close_all_sessions()');
patch('src/core_main.rs', '    crate::load_custom_client();', '    #[cfg(all(any(target_os = "macos", target_os = "windows"), feature = "azsign-access-poc"))]\n    { *config::APP_NAME.write().ok()? = "AZSignRemotePilot".to_owned(); }\n    #[cfg(not(all(any(target_os = "macos", target_os = "windows"), feature = "azsign-access-poc")))]\n    crate::load_custom_client();');
patch('src/flutter_ffi.rs', '    if custom_client_config.is_empty() {', '    #[cfg(not(all(any(target_os = "macos", target_os = "windows"), feature = "azsign-access-poc")))]\n    if custom_client_config.is_empty() {');
if (!readFileSync(join(root, 'libs/hbb_common/src/lib.rs'), 'utf8').includes('pub mod azsign_access;'))
patch('libs/hbb_common/src/lib.rs', 'pub mod socket_client;', '#[cfg(feature = "azsign-access-poc")]\npub mod azsign_access;\npub mod socket_client;');
copyFileSync(join(import.meta.dirname, 'azsign_access.rs'), join(root, 'libs/hbb_common/src/azsign_access.rs'));
patch('libs/hbb_common/src/socket_client.rs', ') -> ResultType<crate::Stream> {', ') -> ResultType<crate::Stream> {\n    #[cfg(feature = "azsign-access-poc")]\n    return crate::azsign_access::tcp(&target.to_string(), ms_timeout).await;');
patch('libs/hbb_common/src/socket_client.rs', ') -> ResultType<Stream> {', ') -> ResultType<Stream> {\n    #[cfg(feature = "azsign-access-poc")]\n    return crate::azsign_access::tcp(&target.to_string(), ms_timeout).await;');
patch('libs/hbb_common/src/socket_client.rs', ') -> ResultType<(FramedSocket, TargetAddr<\'static>)> {', ') -> ResultType<(FramedSocket, TargetAddr<\'static>)> {\n    #[cfg(feature = "azsign-access-poc")]\n    return crate::azsign_access::udp(target, ms_timeout).await;');
patch('libs/hbb_common/src/socket_client.rs', ') -> ResultType<Option<(FramedSocket, TargetAddr<\'static>)>> {', ') -> ResultType<Option<(FramedSocket, TargetAddr<\'static>)>> {\n    #[cfg(feature = "azsign-access-poc")]\n    return Ok(Some(crate::azsign_access::udp(target, 5000).await?));');
patch('libs/hbb_common/src/udp.rs', 'pub enum FramedSocket {', 'pub enum FramedSocket {\n    #[cfg(feature = "azsign-access-poc")]\n    AzsignAccess(crate::tcp::FramedStream, TargetAddr<\'static>),');
patch('libs/hbb_common/src/udp.rs', '            Self::ProxySocks(f) => f.send((send_data, addr)).await?,', '            #[cfg(feature = "azsign-access-poc")]\n            Self::AzsignAccess(f, allowed) => {\n                if addr.to_string() != allowed.to_string() { anyhow::bail!("PoC UDP destination denied"); }\n                f.send_bytes(send_data).await?;\n            },\n            Self::ProxySocks(f) => f.send((send_data, addr)).await?,');
patch('libs/hbb_common/src/udp.rs', '            Self::ProxySocks(f) => f.send((Bytes::from(msg), addr)).await?,', '            #[cfg(feature = "azsign-access-poc")]\n            Self::AzsignAccess(_, _) => anyhow::bail!("PoC raw UDP denied"),\n            Self::ProxySocks(f) => f.send((Bytes::from(msg), addr)).await?,');
patch('libs/hbb_common/src/udp.rs', '            Self::ProxySocks(f) => match f.next().await {', '            #[cfg(feature = "azsign-access-poc")]\n            Self::AzsignAccess(f, addr) => f.next().await.map(|result| result.map(|bytes| (bytes, addr.clone())).map_err(Into::into)),\n            Self::ProxySocks(f) => match f.next().await {');
if (!process.argv.includes('--desktop')) {
patch('flutter/ndk_arm.sh', '--features flutter,hwcodec', '--features flutter,hwcodec,azsign-access-poc');
const java = 'flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/';
copyFileSync(join(import.meta.dirname, 'AzsignAccessPocProvider.java'), join(root, java, 'AzsignAccessPocProvider.java'));
copyFileSync(join(import.meta.dirname, 'AzsignAccessIdentity.java'), join(root, java, 'AzsignAccessIdentity.java'));
copyFileSync(join(import.meta.dirname, 'AzsignRenewalScheduler.java'), join(root, java, 'AzsignRenewalScheduler.java'));
for (const source of ['AzsignRenewalHttp.java', 'AzsignRenewalRuntime.java']) {
  copyFileSync(join(import.meta.dirname, source), join(root, java, source));
}
patch(java + 'MainApplication.kt', 'FFI.onAppStart(applicationContext)', 'FFI.onAppStart(applicationContext)\n        AzsignRenewalRuntime.start(filesDir)');
patch('flutter/android/app/build.gradle', 'dependencies {', "dependencies {\n    implementation 'org.bouncycastle:bcpkix-jdk15to18:1.86'");
patch('flutter/android/app/src/main/AndroidManifest.xml', '</application>', '    <provider android:name=".AzsignAccessPocProvider" android:authorities="com.carriez.flutter_hbb.azsign.accesspoc" android:exported="true" />\n    </application>');
patch('flutter/android/app/src/main/AndroidManifest.xml', 'android:name=".MainApplication"', 'android:name=".MainApplication"\n        android:allowBackup="false"');
}
patch('libs/hbb_common/src/socket_client.rs', 'pub async fn new_direct_udp_for(target: &str) -> ResultType<(Arc<UdpSocket>, SocketAddr)> {', 'pub async fn new_direct_udp_for(target: &str) -> ResultType<(Arc<UdpSocket>, SocketAddr)> {\n    #[cfg(feature = "azsign-access-poc")]\n    anyhow::bail!("PoC direct UDP denied");');
patch('src/rendezvous_mediator.rs', 'async fn direct_server(server: ServerPtr) {', 'async fn direct_server(server: ServerPtr) {\n    #[cfg(feature = "azsign-access-poc")]\n    return;');
console.log('PoC transport hooks applied; no credentials embedded');

// Desktop Windows uses DPAPI user-bound records, never the old file harness.
if (process.argv.includes('--desktop')) {
  patch('libs/hbb_common/Cargo.toml', '\n[dependencies]\n', '\n[target.\'cfg(windows)\'.dependencies]\nopenssl = { version = "0.10", features = ["vendored"] }\nwinapi = { version = "0.3", features = ["dpapi", "wincrypt", "winbase"] }\n\n[dependencies]\n');
  if (!readFileSync(join(root, 'libs/hbb_common/src/lib.rs'), 'utf8').includes('pub mod azsign_windows;'))
  patch('libs/hbb_common/src/lib.rs', 'pub mod socket_client;', '#[cfg(all(windows, feature = "azsign-access-poc"))]\npub mod azsign_windows;\npub mod socket_client;');
  copyFileSync(join(import.meta.dirname, 'azsign_windows.rs'), join(root, 'libs/hbb_common/src/azsign_windows.rs'));
  patch('src/lib.rs', 'mod keyboard;', '#[cfg(all(windows, feature = "azsign-access-poc", feature = "flutter"))]\nmod azsign_windows_ffi;\nmod keyboard;');
}
