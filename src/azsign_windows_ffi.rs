//! Narrow ABI for the Windows desktop UI. Never returns enrollment/private keys.
/// Per-user registration also supports the portable ZIP, without elevation.
pub fn register_remote_protocol() -> std::io::Result<()> {
    use winreg::{enums::HKEY_CURRENT_USER, RegKey};
    let executable = std::env::current_exe()?;
    let root = RegKey::predef(HKEY_CURRENT_USER);
    let (key, _) = root.create_subkey(r"Software\Classes\azsign-remote")?;
    key.set_value("", &"URL:AZSign Remote")?;
    key.set_value("URL Protocol", &"")?;
    let (command, _) = key.create_subkey(r"shell\open\command")?;
    command.set_value("", &format!("\"{}\" \"%1\"", executable.display()))?;
    Ok(())
}

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[no_mangle]
pub unsafe extern "C" fn azsign_windows_dispatch(input: *const c_char) -> *mut c_char {
    let result = std::panic::catch_unwind(|| -> hbb_common::ResultType<serde_json::Value> {
        if input.is_null() {
            hbb_common::anyhow::bail!("Missing request");
        }
        let bytes = CStr::from_ptr(input).to_bytes();
        if bytes.len() > 65536 {
            hbb_common::anyhow::bail!("Request oversized");
        }
        let request: serde_json::Value = serde_json::from_slice(bytes)?;
        let method = request["method"]
            .as_str()
            .ok_or_else(|| hbb_common::anyhow::anyhow!("Missing method"))?;
        // Close every local session even if secure-store removal fails.
        if method == "azsignIdentityClear" {
            crate::flutter::sessions::close_all_sessions();
        }
        hbb_common::azsign_windows::dispatch(method, &request["args"])
    });
    let response = match result {
        Ok(Ok(value)) => serde_json::json!({"ok": true, "value": value}),
        // Do not expose OpenSSL/OS messages that might contain sensitive input.
        _ => serde_json::json!({"ok": false, "error": "Native secure operation failed"}),
    };
    CString::new(response.to_string()).unwrap().into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn azsign_windows_free(value: *mut c_char) {
    if !value.is_null() {
        drop(CString::from_raw(value));
    }
}
