#[cfg(any(test, not(target_os = "linux")))]
mod audio_resampler;
#[cfg(all(windows, feature = "azsign-access-poc", feature = "flutter"))]
mod azsign_windows_ffi;
mod keyboard;
#[cfg(all(any(target_os = "macos", target_os = "windows"), feature = "azsign-access-poc"))]
#[no_mangle]
pub extern "C" fn azsign_native_access_enabled() -> i32 { 1 }
/// cbindgen:ignore
pub mod platform;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub use platform::{
    clip_cursor, get_cursor, get_cursor_data, get_cursor_pos, get_focused_display,
    set_cursor_pos, start_os_service,
};
#[cfg(not(any(target_os = "ios")))]
/// cbindgen:ignore
mod server;
#[cfg(not(any(target_os = "ios")))]
pub use self::server::*;
mod client;
mod lan;
#[cfg(not(any(target_os = "ios")))]
mod rendezvous_mediator;
#[cfg(not(any(target_os = "ios")))]
pub use self::rendezvous_mediator::*;
/// cbindgen:ignore
pub mod common;
#[cfg(not(any(target_os = "ios")))]
pub mod ipc;
#[cfg(not(any(
    target_os = "android",
    target_os = "ios",
    feature = "flutter"
)))]
pub mod ui;
mod version;
pub use version::*;
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
mod bridge_generated;
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
pub mod flutter;
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
pub mod flutter_ffi;
use common::*;
mod auth_2fa;
#[cfg(not(target_os = "ios"))]
mod clipboard;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub mod core_main;
mod custom_server;
mod lang;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod port_forward;
mod port_forward_mux;
#[cfg(all(target_os = "macos", feature = "azsign-access-poc", feature = "flutter"))]
#[no_mangle]
pub extern "C" fn azsign_native_access_logout() { crate::flutter::sessions::close_all_sessions(); }

#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod tray;

#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod whiteboard;

#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod updater;

mod ui_cm_interface;
mod ui_interface;
mod ui_session_interface;

mod hbbs_http;

#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
pub mod clipboard_file;

pub mod privacy_mode;

#[cfg(windows)]
pub mod virtual_display_manager;

mod kcp_stream;
