//! Test-build-only transport. Never falls back to an unprotected endpoint.
use crate::{anyhow::{bail, Context}, tcp::FramedStream, ResultType};
use serde_derive::Deserialize;
use base64::{engine::general_purpose::STANDARD, Engine as _};
use std::{convert::TryFrom, path::PathBuf, sync::Arc};
use tokio::net::TcpStream;
use tokio_rustls::{TlsConnector, rustls::{self, ClientConfig, RootCertStore, pki_types::{CertificateDer, PrivatePkcs8KeyDer, ServerName}}};

#[path = "azsign_domain_alias.rs"]
mod domain_alias;

#[derive(Clone, Deserialize)]
struct Profile { host: String, server_name: String, registration: u16, rendezvous: u16, relay: u16 }

#[derive(Deserialize)]
struct Enrollment {
    identity_id: String,
    profile: Profile,
    certificate_base64: String,
    ca_base64: String,
    #[serde(default)]
    expires_at: Option<u64>,
}

#[cfg(any(target_os = "macos", target_os = "windows"))]
#[derive(Deserialize)]
struct DesktopEnrollment {
    #[serde(flatten)]
    enrollment: Enrollment,
    active: bool,
    private_pkcs8: String,
}

#[cfg(any(target_os = "macos", target_os = "windows"))]
fn desktop_enrollment() -> ResultType<DesktopEnrollment> {
    #[cfg(target_os = "macos")]
    let bytes = security_framework::passwords::get_generic_password(
        "com.azsign.rustdesk.desktop", "azsign_desktop_enrollment")?;
    #[cfg(target_os = "windows")]
    let bytes = crate::azsign_windows::enrollment_bytes()?;
    parse_desktop_enrollment(&bytes)
}

#[cfg(any(target_os = "macos", target_os = "windows"))]
fn parse_desktop_enrollment(bytes: &[u8]) -> ResultType<DesktopEnrollment> {
    if bytes.len() > 32768 { bail!("Desktop enrollment oversized"); }
    let record: DesktopEnrollment = serde_json::from_slice(bytes)?;
    uuid::Uuid::parse_str(&record.enrollment.identity_id)?;
    let expiry = record.enrollment.expires_at.context("Desktop enrollment expiry required")?;
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)?.as_millis();
    if !record.active || now >= u128::from(expiry) {
        bail!("Desktop enrollment inactive or expired");
    }
    Ok(record)
}

fn credentials(dir: &std::path::Path) -> ResultType<(Profile, Vec<u8>, Vec<u8>, Vec<u8>)> {
    #[cfg(target_os = "android")]
    {
        // A single committed public enrollment snapshot; no legacy key-import fallback.
        let bytes = std::fs::read(dir.join("active.json"))?;
        if bytes.len() > 32768 { bail!("Enrollment oversized"); }
        let active: Enrollment = serde_json::from_slice(&bytes)?;
        uuid::Uuid::parse_str(&active.identity_id)?;
        let identity = std::fs::read_to_string(dir.join("identity/id"))?;
        if identity != active.identity_id { bail!("Enrollment identity mismatch"); }
        if let Some(exp) = active.expires_at {
            if let Ok(duration) = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH) {
                let now = duration.as_secs();
                let exp_secs = if exp > 1_000_000_000_000 { exp / 1000 } else { exp };
                if now > exp_secs {
                    bail!("Client certificate expired; remote transport unauthorized");
                }
            }
        }
        Ok((active.profile, STANDARD.decode(active.ca_base64)?, STANDARD.decode(active.certificate_base64)?,
            std::fs::read(dir.join("identity/key.der"))?))
    }
    #[cfg(any(target_os = "macos", target_os = "windows"))]
    {
        let record = desktop_enrollment()?;
        Ok((record.enrollment.profile, STANDARD.decode(record.enrollment.ca_base64)?,
            STANDARD.decode(record.enrollment.certificate_base64)?, STANDARD.decode(record.private_pkcs8)?))
    }
    #[cfg(not(any(target_os = "android", target_os = "macos", target_os = "windows")))]
    {
        // Existing local desktop harness until native operator enrollment is integrated.
        Ok((serde_json::from_slice(&std::fs::read(dir.join("profile.json"))?)?,
            std::fs::read(dir.join("ca.der"))?, std::fs::read(dir.join("device.der"))?,
            std::fs::read(dir.join("device.key.der"))?))
    }
}

fn load_profile(dir: &std::path::Path) -> ResultType<Profile> {
    #[cfg(target_os = "android")]
    {
        let bytes = std::fs::read(dir.join("active.json"))?;
        if bytes.len() > 32768 { bail!("Enrollment oversized"); }
        let active: Enrollment = serde_json::from_slice(&bytes)?;
        uuid::Uuid::parse_str(&active.identity_id)?;
        Ok(active.profile)
    }
    #[cfg(any(target_os = "macos", target_os = "windows"))]
    { Ok(desktop_enrollment()?.enrollment.profile) }
    #[cfg(not(any(target_os = "android", target_os = "macos", target_os = "windows")))]
    {
        Ok(serde_json::from_slice(&std::fs::read(dir.join("profile.json"))?)?)
    }
}

fn parse_target(target: &str) -> ResultType<(&str, Option<u16>)> {
    if let Some((host, port_str)) = target.rsplit_once(':') {
        let host = host.trim_start_matches('[').trim_end_matches(']');
        if let Ok(port) = port_str.parse::<u16>() {
            return Ok((host, Some(port)));
        }
    }
    Ok((target.trim_start_matches('[').trim_end_matches(']'), None))
}

fn directory() -> ResultType<PathBuf> {
    #[cfg(target_os = "android")]
    return Ok(PathBuf::from("/data/data/com.carriez.flutter_hbb/files/azsign-access-poc"));
    #[cfg(any(target_os = "macos", target_os = "windows"))]
    return Ok(PathBuf::new()); // macOS credentials are Keychain-only; this path is never read.
    #[cfg(not(any(target_os = "android", target_os = "macos", target_os = "windows")))]
    Ok(std::env::var_os("AZSIGN_ACCESS_POC_DIR").context("PoC profile required")?.into())
}

pub async fn connect(service: &str, milliseconds: u64) -> ResultType<FramedStream> {
    let dir = directory()?;
    let (profile, config) = tokio::task::spawn_blocking(move || -> ResultType<_> {
        let (profile, ca, certificate, key) = credentials(&dir)?;
        let mut roots = RootCertStore::empty();
        roots.add(CertificateDer::from(ca))?;
        let certificate = CertificateDer::from(certificate);
        let key = PrivatePkcs8KeyDer::from(key);
        let mut config = ClientConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
            .with_protocol_versions(&[&rustls::version::TLS13])?
            .with_root_certificates(roots)
            .with_client_auth_cert(vec![certificate], key.into())?;
        config.resumption = rustls::client::Resumption::disabled();
        config.enable_early_data = false;
        Ok((profile, config))
    }).await??;
    let port = match service {
        "registration" => profile.registration,
        "rendezvous" => profile.rendezvous,
        "relay" => profile.relay,
        _ => bail!("PoC service denied"),
    };
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
    let (host, port) = parse_target(target)?;

    // IPC uses parity_tokio_ipc, not this remote transport. Even loopback must
    // match the enrolled gateway and traverse TLS; no arbitrary local relay.
    let dir = directory()?;
    let profile = tokio::task::spawn_blocking(move || load_profile(&dir)).await??;
    if !domain_alias::accepts(host, &profile.host, &profile.server_name) {
        bail!("PoC forbids direct/public TCP targets: {}", target);
    }

    let service = match port {
        Some(p) if p == profile.rendezvous || p == 21116 => "rendezvous",
        Some(p) if p == profile.relay || p == 21117 => "relay",
        Some(p) if p == profile.registration || p == 32116 => "registration",
        None => "rendezvous",
        Some(p) => bail!("PoC forbids unrecognized port for gateway: {}", p),
    };
    Ok(crate::Stream::Tcp(connect(service, milliseconds).await?))
}

pub async fn udp(target: &str, milliseconds: u64) -> ResultType<(crate::udp::FramedSocket, crate::TargetAddr<'static>)> {
    let (host, port) = parse_target(target)?;
    let dir = directory()?;
    let profile = tokio::task::spawn_blocking(move || load_profile(&dir)).await??;

    if !domain_alias::accepts(host, &profile.host, &profile.server_name) {
        bail!("PoC forbids direct/public UDP targets: {}", target);
    }

    if let Some(p) = port {
        if p != profile.registration && p != profile.rendezvous && p != 21116 && p != 32116 {
            bail!("PoC forbids unrecognized UDP port: {}", p);
        }
    }

    use crate::IntoTargetAddr;
    let addr = target.into_target_addr()?.to_owned();
    let stream = connect("registration", milliseconds).await?;
    Ok((crate::udp::FramedSocket::AzsignAccess(stream, addr.clone()), addr))
}

#[cfg(all(test, target_os = "macos"))]
mod desktop_tests {
    use super::*;

    #[test]
    fn desktop_record_requires_active_identity_and_absolute_future_expiry() {
        let mut record = serde_json::json!({
            "identity_id": "01a0df99-c0f2-72fe-9f31-58742f0c8555",
            "profile": {"host": "gateway.example", "server_name": "gateway.example", "registration": 32116, "rendezvous": 32117, "relay": 32118},
            "active": true, "private_pkcs8": "", "certificate_base64": "", "ca_base64": "",
            "expires_at": 4102444800000u64
        });
        let parse = |value: &serde_json::Value| parse_desktop_enrollment(value.to_string().as_bytes());
        assert!(parse(&record).is_ok());
        record["expires_at"] = 1.into();
        assert!(parse(&record).is_err());
        record["expires_at"] = serde_json::Value::Null;
        assert!(parse(&record).is_err());
        record["expires_at"] = 4102444800000u64.into();
        record["active"] = false.into();
        assert!(parse(&record).is_err());
        record["active"] = true.into();
        record["identity_id"] = "invalid".into();
        assert!(parse(&record).is_err());
        assert!(parse_desktop_enrollment(&vec![0; 32769]).is_err());
    }
}
