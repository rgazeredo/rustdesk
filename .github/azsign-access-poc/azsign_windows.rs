//! Windows-only native enrollment. DPAPI is user-bound, never machine-wide.
//! Only public CSR/certificate metadata and the login token cross the UI boundary.
use anyhow::{bail, Context, Result};
use base64::{engine::general_purpose::STANDARD, Engine};
use openssl::{
    hash::MessageDigest,
    nid::Nid,
    pkey::PKey,
    rsa::Rsa,
    stack::Stack,
    x509::{
        store::X509StoreBuilder, verify::X509VerifyFlags, X509NameBuilder, X509PurposeId, X509Req,
        X509StoreContext, X509,
    },
};
use serde_json::{json, Value};
use std::os::windows::ffi::OsStrExt;
use std::{fs, io::Write, path::PathBuf, ptr, sync::Mutex};
use winapi::um::{
    dpapi::{CryptProtectData, CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN},
    winbase::{LocalFree, MoveFileExW, MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH},
    wincrypt::DATA_BLOB,
};

static LOCK: Mutex<()> = Mutex::new(());
const ENROLLMENT: &str = "azsign_desktop_enrollment";
const MAX: usize = 32768;

fn path(key: &str) -> Result<PathBuf> {
    if ![
        ENROLLMENT,
        "azsign_desktop_device_id",
        "azsign_desktop_access_token",
    ]
    .contains(&key)
    {
        bail!("Unknown secure record");
    }
    #[cfg(not(test))]
    let root = dirs_next::data_local_dir()
        .context("Windows user profile unavailable")?
        .join("AZSignRemotePilot")
        .join("SecureStore");
    #[cfg(test)]
    let root = std::env::temp_dir().join(format!("azsign-native-test-{}", std::process::id()));
    Ok(root.join(format!("{}.dpapi", key)))
}

fn crypt(bytes: &[u8], encrypt: bool) -> Result<Vec<u8>> {
    if bytes.len() > MAX + 4096 {
        bail!("Secure record oversized");
    }
    let mut input = DATA_BLOB {
        cbData: bytes.len() as u32,
        pbData: bytes.as_ptr() as *mut u8,
    };
    let mut output = DATA_BLOB {
        cbData: 0,
        pbData: ptr::null_mut(),
    };
    // Fixed application entropy separates these records from other DPAPI uses.
    let entropy = b"com.azsign.rustdesk.desktop.v1";
    let mut extra = DATA_BLOB {
        cbData: entropy.len() as u32,
        pbData: entropy.as_ptr() as *mut u8,
    };
    unsafe {
        let ok = if encrypt {
            CryptProtectData(
                &mut input,
                ptr::null(),
                &mut extra,
                ptr::null_mut(),
                ptr::null_mut(),
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut output,
            )
        } else {
            CryptUnprotectData(
                &mut input,
                ptr::null_mut(),
                &mut extra,
                ptr::null_mut(),
                ptr::null_mut(),
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut output,
            )
        };
        if ok == 0 {
            bail!("Windows secure storage unavailable");
        }
        let value = std::slice::from_raw_parts(output.pbData, output.cbData as usize).to_vec();
        // Do not leave the Windows-allocated plaintext buffer behind.
        for i in 0..output.cbData as usize {
            ptr::write_volatile(output.pbData.add(i), 0);
        }
        LocalFree(output.pbData as _);
        Ok(value)
    }
}

fn read(key: &str) -> Result<Option<Vec<u8>>> {
    let file = match fs::File::open(path(key)?) {
        Ok(file) => file,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(e.into()),
    };
    if file.metadata()?.len() > (MAX + 4096) as u64 {
        bail!("Secure record oversized");
    }
    use std::io::Read;
    let mut bytes = Vec::new();
    file.take((MAX + 4097) as u64).read_to_end(&mut bytes)?;
    let plain = crypt(&bytes, false)?;
    if plain.len() > MAX {
        bail!("Secure record oversized");
    }
    Ok(Some(plain))
}

fn write(key: &str, bytes: &[u8]) -> Result<()> {
    if bytes.len() > MAX {
        bail!("Secure record oversized");
    }
    let encrypted = crypt(bytes, true)?;
    let target = path(key)?;
    fs::create_dir_all(target.parent().context("Missing storage directory")?)?;
    let temporary = target.with_extension(format!("{}.tmp", uuid::Uuid::new_v4()));
    let result = (|| -> Result<()> {
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)?;
        file.write_all(&encrypted)?;
        file.sync_all()?;
        drop(file);
        let src: Vec<u16> = temporary.as_os_str().encode_wide().chain(Some(0)).collect();
        let dst: Vec<u16> = target.as_os_str().encode_wide().chain(Some(0)).collect();
        if unsafe {
            MoveFileExW(
                src.as_ptr(),
                dst.as_ptr(),
                MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
            )
        } == 0
        {
            return Err(std::io::Error::last_os_error().into());
        }
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(temporary);
    }
    result
}

fn delete(key: &str) -> Result<()> {
    match fs::remove_file(path(key)?) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e.into()),
    }
}

pub fn enrollment_bytes() -> Result<Vec<u8>> {
    let _guard = LOCK
        .lock()
        .map_err(|_| anyhow::anyhow!("Storage lock unavailable"))?;
    read(ENROLLMENT)?.context("Operator enrollment required")
}

fn text<'a>(value: &'a Value, key: &str) -> Result<&'a str> {
    value[key].as_str().context("Missing enrollment field")
}

fn prepare(identity: &str) -> Result<Value> {
    uuid::Uuid::parse_str(identity)?;
    let saved = read(ENROLLMENT)?
        .map(|b| serde_json::from_slice::<Value>(&b))
        .transpose()?;
    let key = if let Some(record) = saved.filter(|r| r["identity_id"] == identity) {
        PKey::private_key_from_pkcs8(&STANDARD.decode(text(&record, "private_pkcs8")?)?)?
    } else {
        let key = PKey::from_rsa(Rsa::generate(2048)?)?;
        write(
            ENROLLMENT,
            &serde_json::to_vec(&json!({"identity_id": identity, "active": false,
            "private_pkcs8": STANDARD.encode(key.private_key_to_pkcs8()?)}))?,
        )?;
        key
    };
    let mut name = X509NameBuilder::new()?;
    name.append_entry_by_nid(Nid::COMMONNAME, identity)?;
    let mut csr = X509Req::builder()?;
    csr.set_version(0)?;
    csr.set_subject_name(&name.build())?;
    csr.set_pubkey(&key)?;
    csr.sign(&key, MessageDigest::sha256())?;
    Ok(json!({"identity_id": identity, "csr": String::from_utf8(csr.build().to_pem()?)?}))
}

fn install(args: &Value) -> Result<Value> {
    let identity = text(args, "identity_id")?;
    uuid::Uuid::parse_str(identity)?;
    let mut record: Value =
        serde_json::from_slice(&read(ENROLLMENT)?.context("Prepare identity first")?)?;
    if record["identity_id"] != identity {
        bail!("Identity mismatch");
    }
    let profile = &args["profile"];
    for field in ["host", "server_name"] {
        let host = text(profile, field)?;
        if host.is_empty()
            || host.len() > 253
            || !host
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-')
        {
            bail!("Invalid gateway name");
        }
    }
    for field in ["registration", "rendezvous", "relay"] {
        if !(1024..=65535).contains(&profile[field].as_u64().context("Invalid gateway port")?) {
            bail!("Invalid gateway port");
        }
    }
    let pem = text(args, "certificate")?;
    let ca_pem = text(args, "ca_certificate")?;
    if pem.len() > 16384 || ca_pem.len() > 16384 {
        bail!("Certificate oversized");
    }
    let leaf = X509::from_pem(pem.as_bytes())?;
    let ca = X509::from_pem(ca_pem.as_bytes())?;
    let entries: Vec<_> = leaf.subject_name().entries().collect();
    if entries.len() != 1
        || entries[0].object().nid() != Nid::COMMONNAME
        || entries[0].data().as_slice() != identity.as_bytes()
    {
        bail!("Certificate subject mismatch");
    }
    let private = PKey::private_key_from_pkcs8(&STANDARD.decode(text(&record, "private_pkcs8")?)?)?;
    if !leaf.public_key()?.public_eq(&private) {
        bail!("Certificate key mismatch");
    }
    let mut store = X509StoreBuilder::new()?;
    store.add_cert(ca.clone())?;
    store.set_flags(X509VerifyFlags::PARTIAL_CHAIN)?;
    store.set_purpose(X509PurposeId::SSL_CLIENT)?;
    if !X509StoreContext::new()?.init(&store.build(), &leaf, &Stack::new()?, |ctx| {
        ctx.verify_cert()
    })? {
        bail!("Untrusted or expired client certificate");
    }
    let now = chrono::Utc::now().timestamp_millis();
    let epoch = openssl::asn1::Asn1Time::from_unix(0)?;
    let diff = epoch.diff(leaf.not_after())?;
    let certificate_expiry = (i64::from(diff.days) * 86400 + i64::from(diff.secs)) * 1000;
    let expiry = [
        certificate_expiry,
        chrono::DateTime::parse_from_rfc3339(text(args, "expires_at")?)?.timestamp_millis(),
        chrono::DateTime::parse_from_rfc3339(text(args, "session_expires_at")?)?.timestamp_millis(),
    ]
    .iter()
    .copied()
    .min()
    .context("Missing expiry")?;
    if expiry <= now {
        bail!("Session expired");
    }
    record["profile"] = profile.clone();
    record["certificate_base64"] = json!(STANDARD.encode(leaf.to_der()?));
    record["ca_base64"] = json!(STANDARD.encode(ca.to_der()?));
    record["expires_at"] = json!(expiry);
    record["active"] = json!(true);
    write(ENROLLMENT, &serde_json::to_vec(&record)?)?;
    Ok(json!({"identity_id": identity, "expires_at": expiry}))
}

pub fn dispatch(method: &str, args: &Value) -> Result<Value> {
    let _guard = LOCK
        .lock()
        .map_err(|_| anyhow::anyhow!("Storage lock unavailable"))?;
    match method {
        "azsignNativeTransportAvailable" => Ok(json!(true)),
        "azsignIdentityPrepare" => prepare(text(args, "identity_id")?),
        "azsignIdentityInstall" => install(args),
        "azsignIdentityClear" => {
            delete(ENROLLMENT)?;
            Ok(Value::Null)
        }
        "azsignSecureRead" | "azsignSecureWrite" | "azsignSecureDelete" => {
            let key = text(args, "key")?;
            if key == ENROLLMENT {
                bail!("Private enrollment is native-only");
            }
            match method {
                "azsignSecureRead" => Ok(read(key)?
                    .map(String::from_utf8)
                    .transpose()?
                    .map(Value::String)
                    .unwrap_or(Value::Null)),
                "azsignSecureWrite" => {
                    let value = text(args, "value")?;
                    if value.len() > 4096 {
                        bail!("Token oversized");
                    }
                    write(key, value.as_bytes())?;
                    Ok(Value::Null)
                }
                _ => {
                    delete(key)?;
                    Ok(Value::Null)
                }
            }
        }
        _ => bail!("Unknown native method"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use openssl::{
        asn1::Asn1Time,
        bn::BigNum,
        x509::extension::{BasicConstraints, ExtendedKeyUsage, KeyUsage},
    };
    #[test]
    fn dpapi_round_trip_and_tampering() {
        let value = b"ephemeral-test-not-a-real-key";
        let mut encrypted = crypt(value, true).unwrap();
        assert!(!encrypted.windows(value.len()).any(|w| w == value));
        assert_eq!(crypt(&encrypted, false).unwrap(), value);
        let last = encrypted.len() - 1;
        encrypted[last] ^= 1;
        assert!(crypt(&encrypted, false).is_err());
    }
    #[test]
    fn ui_cannot_read_private_record_or_arbitrary_paths() {
        assert!(dispatch("azsignSecureRead", &json!({"key": ENROLLMENT})).is_err());
        assert!(dispatch("azsignSecureRead", &json!({"key": "../../anything"})).is_err());
        assert!(dispatch("azsignIdentityPrepare", &json!({"identity_id": "bad"})).is_err());
    }

    #[test]
    fn enrollment_csr_validation_expiry_and_logout() {
        let id = uuid::Uuid::new_v4().to_string();
        let prepared = dispatch("azsignIdentityPrepare", &json!({"identity_id": id})).unwrap();
        assert!(prepared.get("private_pkcs8").is_none());
        let csr = X509Req::from_pem(prepared["csr"].as_str().unwrap().as_bytes()).unwrap();
        let public = csr.public_key().unwrap();
        assert!(csr.verify(&public).unwrap());
        assert_eq!(csr.subject_name().entries().count(), 1);
        let again = dispatch("azsignIdentityPrepare", &json!({"identity_id": id})).unwrap();
        assert_eq!(prepared, again);
        let ca_key = PKey::from_rsa(Rsa::generate(2048).unwrap()).unwrap();
        let mut ca_name = X509NameBuilder::new().unwrap();
        ca_name
            .append_entry_by_nid(Nid::COMMONNAME, "Test CA")
            .unwrap();
        let ca_name = ca_name.build();
        let mut ca = X509::builder().unwrap();
        ca.set_version(2).unwrap();
        ca.set_serial_number(&BigNum::from_u32(1).unwrap().to_asn1_integer().unwrap())
            .unwrap();
        ca.set_subject_name(&ca_name).unwrap();
        ca.set_issuer_name(&ca_name).unwrap();
        ca.set_pubkey(&ca_key).unwrap();
        ca.set_not_before(&Asn1Time::days_from_now(0).unwrap())
            .unwrap();
        ca.set_not_after(&Asn1Time::days_from_now(2).unwrap())
            .unwrap();
        ca.append_extension(BasicConstraints::new().critical().ca().build().unwrap())
            .unwrap();
        ca.append_extension(KeyUsage::new().key_cert_sign().build().unwrap())
            .unwrap();
        ca.sign(&ca_key, MessageDigest::sha256()).unwrap();
        let ca = ca.build();
        let make_leaf = |key: &openssl::pkey::PKeyRef<openssl::pkey::Public>, client: bool| {
            let mut leaf = X509::builder().unwrap();
            leaf.set_version(2).unwrap();
            leaf.set_serial_number(&BigNum::from_u32(2).unwrap().to_asn1_integer().unwrap())
                .unwrap();
            leaf.set_subject_name(csr.subject_name()).unwrap();
            leaf.set_issuer_name(ca.subject_name()).unwrap();
            leaf.set_pubkey(key).unwrap();
            leaf.set_not_before(&Asn1Time::days_from_now(0).unwrap())
                .unwrap();
            leaf.set_not_after(&Asn1Time::days_from_now(1).unwrap())
                .unwrap();
            leaf.append_extension(BasicConstraints::new().critical().build().unwrap())
                .unwrap();
            leaf.append_extension(KeyUsage::new().digital_signature().build().unwrap())
                .unwrap();
            let mut usage = ExtendedKeyUsage::new();
            if client {
                usage.client_auth();
            } else {
                usage.server_auth();
            }
            leaf.append_extension(usage.build().unwrap()).unwrap();
            leaf.sign(&ca_key, MessageDigest::sha256()).unwrap();
            String::from_utf8(leaf.build().to_pem().unwrap()).unwrap()
        };
        let now = chrono::Utc::now();
        let mut args = json!({"identity_id": id,
            "profile": {"host":"rustdesk.example.com", "server_name":"rustdesk.example.com", "registration":32116,"rendezvous":32117,"relay":32118},
            "ca_certificate":String::from_utf8(ca.to_pem().unwrap()).unwrap(),
            "certificate":make_leaf(&public, true),
            "expires_at": (now + chrono::Duration::hours(24)).to_rfc3339(),
            "session_expires_at": (now + chrono::Duration::hours(1)).to_rfc3339()});
        dispatch("azsignIdentityInstall", &args).unwrap();
        let active: Value = serde_json::from_slice(&enrollment_bytes().unwrap()).unwrap();
        assert_eq!(active["active"], true);
        assert!(
            active["expires_at"].as_i64().unwrap()
                <= (now + chrono::Duration::hours(1)).timestamp_millis()
        );
        args["certificate"] = json!(make_leaf(&public, false));
        assert!(dispatch("azsignIdentityInstall", &args).is_err());
        let other = PKey::public_key_from_der(&ca_key.public_key_to_der().unwrap()).unwrap();
        args["certificate"] = json!(make_leaf(&other, true));
        assert!(dispatch("azsignIdentityInstall", &args).is_err());
        args["certificate"] = json!(make_leaf(&public, true));
        args["session_expires_at"] = json!((now - chrono::Duration::hours(1)).to_rfc3339());
        assert!(dispatch("azsignIdentityInstall", &args).is_err());
        dispatch("azsignIdentityClear", &json!({})).unwrap();
        assert!(enrollment_bytes().is_err());
        assert!(dispatch("azsignIdentityInstall", &args).is_err());
    }
}
