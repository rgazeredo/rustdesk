//! Test-build-only transport. Never falls back to an unprotected endpoint.
use crate::{anyhow::{bail, Context}, tcp::FramedStream, ResultType};
use serde_derive::Deserialize;
use std::{convert::TryFrom, path::PathBuf, sync::Arc};
use tokio::net::TcpStream;
use tokio_rustls::{TlsConnector, rustls::{self, ClientConfig, RootCertStore, pki_types::{CertificateDer, PrivatePkcs8KeyDer, ServerName}}};

#[derive(Deserialize)]
struct Profile { host: String, server_name: String, registration: u16, rendezvous: u16, relay: u16 }

fn directory() -> ResultType<PathBuf> {
    #[cfg(target_os = "android")]
    return Ok(PathBuf::from("/data/data/com.carriez.flutter_hbb/files/azsign-access-poc"));
    #[cfg(not(target_os = "android"))]
    Ok(std::env::var_os("AZSIGN_ACCESS_POC_DIR").context("PoC profile required")?.into())
}

pub async fn connect(service: &str, milliseconds: u64) -> ResultType<FramedStream> {
    let dir = directory()?;
    let (profile, config) = tokio::task::spawn_blocking(move || -> ResultType<_> {
        let profile: Profile = serde_json::from_slice(&std::fs::read(dir.join("profile.json"))?)?;
        let mut roots = RootCertStore::empty();
        roots.add(CertificateDer::from(std::fs::read(dir.join("ca.der"))?))?;
        let certificate = CertificateDer::from(std::fs::read(dir.join("device.der"))?);
        let key = PrivatePkcs8KeyDer::from(std::fs::read(dir.join("device.key.der"))?);
        let mut config = ClientConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
            .with_protocol_versions(&[&rustls::version::TLS13])?
            .with_root_certificates(roots)
            .with_client_auth_cert(vec![certificate], key.into())?;
        config.resumption = rustls::client::Resumption::disabled();
        config.enable_early_data = false;
        Ok((profile, config))
    }).await??;
    let port = match service { "registration" => profile.registration, "rendezvous" => profile.rendezvous, "relay" => profile.relay, _ => bail!("PoC service denied") };
    let name = ServerName::try_from(profile.server_name.clone())?;
    crate::timeout(milliseconds, async {
        let socket = TcpStream::connect((profile.host.as_str(), port)).await?;
        socket.set_nodelay(true)?;
        let local = socket.local_addr()?;
        let tls = TlsConnector::from(Arc::new(config)).connect(name, socket).await?;
        Ok(FramedStream::from(tls, local))
    }).await?
}

pub async fn tcp(target: &str, milliseconds: u64) -> ResultType<crate::Stream> {
    let service = match target {
        "127.0.0.1:21116" => "rendezvous",
        // The private lab server still advertises its logical relay alias.
        "127.0.0.1:21117" | "azsign-poc.invalid:21117" => "relay",
        _ => bail!("PoC forbids direct/public TCP targets"),
    };
    Ok(crate::Stream::Tcp(connect(service, milliseconds).await?))
}

pub async fn udp(target: &str, milliseconds: u64) -> ResultType<(crate::udp::FramedSocket, crate::TargetAddr<'static>)> {
    if target != "127.0.0.1:21116" { bail!("PoC forbids direct/public UDP targets"); }
    use crate::IntoTargetAddr;
    let addr = "127.0.0.1:21116".into_target_addr()?.to_owned();
    let stream = connect("registration", milliseconds).await?;
    Ok((crate::udp::FramedSocket::AzsignAccess(stream, addr.clone()), addr))
}
