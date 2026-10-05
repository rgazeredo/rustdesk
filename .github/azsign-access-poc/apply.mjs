import { readFileSync, writeFileSync, copyFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
const root = resolve(process.argv[2] ?? '.');
function patch(file, old, value) {
  const path = join(root, file);
  const source = readFileSync(path, 'utf8');
  if (source.split(old).length !== 2) throw new Error(`Unexpected patch target: ${file}`);
  writeFileSync(path, source.replace(old, () => value));
}
patch('libs/hbb_common/Cargo.toml', 'default = []', 'default = []\nazsign-access-poc = []');
patch('Cargo.toml', '[features]', '[features]\nazsign-access-poc = ["hbb_common/azsign-access-poc"]');
patch('libs/hbb_common/src/lib.rs', 'pub mod socket_client;', '#[cfg(feature = "azsign-access-poc")]\npub mod azsign_access;\npub mod socket_client;');
copyFileSync(join(import.meta.dirname, 'azsign_access.rs'), join(root, 'libs/hbb_common/src/azsign_access.rs'));
copyFileSync(join(import.meta.dirname, 'azsign_domain_alias.rs'), join(root, 'libs/hbb_common/src/azsign_domain_alias.rs'));
copyFileSync(join(import.meta.dirname, 'azsign_scope.rs'), join(root, 'libs/hbb_common/src/azsign_scope.rs'));
patch('libs/hbb_common/src/lib.rs', 'pub mod azsign_access;', 'pub mod azsign_access;\n#[cfg(feature = "azsign-access-poc")]\npub mod azsign_scope;');
// Keep gateway scope local to the relay task; no shared ConnectionMeta/IPC changes.
patch('src/server.rs', '    let licence_key = crate::get_key(true).await;\n    msg_out.set_request_relay', '    let licence_key = crate::get_key(true).await;\n    #[cfg(all(target_os = "android", feature = "azsign-access-poc"))]\n    let azsign_session_uuid = uuid.clone();\n    msg_out.set_request_relay');
patch('src/server.rs', '    stream.send(&msg_out).await?;\n    create_tcp_connection(server, stream, peer_addr, secure, meta).await?;', '    stream.send(&msg_out).await?;\n    #[cfg(all(target_os = "android", feature = "azsign-access-poc"))]\n    {\n        let scope = hbb_common::azsign_scope::receive(&mut stream, &azsign_session_uuid).await?;\n        return hbb_common::azsign_scope::AUTHORIZED_SCOPE.scope(scope,\n            create_tcp_connection(server, stream, peer_addr, secure, meta)).await;\n    }\n    #[cfg(not(all(target_os = "android", feature = "azsign-access-poc")))]\n    create_tcp_connection(server, stream, peer_addr, secure, meta).await?;');
patch('src/server/connection.rs', '    async fn on_message(&mut self, msg: Message) -> bool {', `    async fn on_message(&mut self, msg: Message) -> bool {
        #[cfg(all(target_os = "android", feature = "azsign-access-poc"))]
        {
            let allowed = match msg.union.as_ref() {
                Some(message::Union::LoginRequest(lr)) => {
                    let kind = match lr.union.as_ref() {
                        None => "remote",
                        Some(login_request::Union::FileTransfer(_)) => "file_transfer",
                        _ => "unsupported",
                    };
                    hbb_common::azsign_scope::allows_login(kind)
                },
                Some(message::Union::FileAction(_)) | Some(message::Union::FileResponse(_)) | Some(message::Union::Cliprdr(_)) => hbb_common::azsign_scope::allows_files(),
                _ => true,
            };
            if !allowed {
                self.send_login_error("Connection not allowed").await;
                self.on_close("AZSign relay scope violation", true).await;
                return false;
            }
        }`);
patch('libs/hbb_common/src/socket_client.rs', ') -> ResultType<crate::Stream> {', ') -> ResultType<crate::Stream> {\n    #[cfg(feature = "azsign-access-poc")]\n    return crate::azsign_access::tcp(&target.to_string(), ms_timeout).await;');
patch('libs/hbb_common/src/socket_client.rs', ') -> ResultType<Stream> {', ') -> ResultType<Stream> {\n    #[cfg(feature = "azsign-access-poc")]\n    return crate::azsign_access::tcp(&target.to_string(), ms_timeout).await;');
patch('libs/hbb_common/src/socket_client.rs', ') -> ResultType<(FramedSocket, TargetAddr<\'static>)> {', ') -> ResultType<(FramedSocket, TargetAddr<\'static>)> {\n    #[cfg(feature = "azsign-access-poc")]\n    return crate::azsign_access::udp(target, ms_timeout).await;');
patch('libs/hbb_common/src/socket_client.rs', ') -> ResultType<Option<(FramedSocket, TargetAddr<\'static>)>> {', ') -> ResultType<Option<(FramedSocket, TargetAddr<\'static>)>> {\n    #[cfg(feature = "azsign-access-poc")]\n    return Ok(Some(crate::azsign_access::udp(target, 5000).await?));');
patch('libs/hbb_common/src/udp.rs', 'pub enum FramedSocket {', 'pub enum FramedSocket {\n    #[cfg(feature = "azsign-access-poc")]\n    AzsignAccess(crate::tcp::FramedStream, TargetAddr<\'static>),');
patch('libs/hbb_common/src/udp.rs', '            Self::ProxySocks(f) => f.send((send_data, addr)).await?,', '            #[cfg(feature = "azsign-access-poc")]\n            Self::AzsignAccess(f, allowed) => {\n                if addr.to_string() != allowed.to_string() { anyhow::bail!("PoC UDP destination denied"); }\n                f.send_bytes(send_data).await?;\n            },\n            Self::ProxySocks(f) => f.send((send_data, addr)).await?,');
patch('libs/hbb_common/src/udp.rs', '            Self::ProxySocks(f) => f.send((Bytes::from(msg), addr)).await?,', '            #[cfg(feature = "azsign-access-poc")]\n            Self::AzsignAccess(_, _) => anyhow::bail!("PoC raw UDP denied"),\n            Self::ProxySocks(f) => f.send((Bytes::from(msg), addr)).await?,');
patch('libs/hbb_common/src/udp.rs', '            Self::ProxySocks(f) => match f.next().await {', '            #[cfg(feature = "azsign-access-poc")]\n            Self::AzsignAccess(f, addr) => f.next().await.map(|result| result.map(|bytes| (bytes, addr.clone())).map_err(Into::into)),\n            Self::ProxySocks(f) => match f.next().await {');
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
patch('libs/hbb_common/src/socket_client.rs', 'pub async fn new_direct_udp_for(target: &str) -> ResultType<(Arc<UdpSocket>, SocketAddr)> {', 'pub async fn new_direct_udp_for(target: &str) -> ResultType<(Arc<UdpSocket>, SocketAddr)> {\n    #[cfg(feature = "azsign-access-poc")]\n    anyhow::bail!("PoC direct UDP denied");');
patch('src/rendezvous_mediator.rs', 'async fn direct_server(server: ServerPtr) {', 'async fn direct_server(server: ServerPtr) {\n    #[cfg(feature = "azsign-access-poc")]\n    return;');
console.log('PoC transport hooks applied; no credentials embedded');
