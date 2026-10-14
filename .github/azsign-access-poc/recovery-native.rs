fn configuration_ready() -> bool {
    // Application.onCreate can start recovery before MainService/Flutter sets
    // APP_DIR. Reading the lazy Config then would generate a new ID/key pair.
    let directory = hbb_common::config::APP_DIR.read().unwrap();
    let path = std::path::Path::new(directory.as_str());
    path.is_absolute() && path.is_dir()
}

#[no_mangle]
pub unsafe extern "system" fn Java_com_carriez_flutter_1hbb_AzsignRecoveryAndroid_deviceId(
    env: jni::JNIEnv, _class: jni::objects::JClass,
) -> jni::sys::jstring {
    let id = if configuration_ready() {
        hbb_common::config::Config::get_id()
    } else {
        String::new()
    };
    env.new_string(id).map(|s| s.into_raw()).unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "system" fn Java_com_carriez_flutter_1hbb_AzsignRecoveryAndroid_applyPassword(
    mut env: jni::JNIEnv, _class: jni::objects::JClass, password: jni::objects::JString,
) -> jni::sys::jboolean {
    if !configuration_ready() { return 0; }
    let password: String = match env.get_string(&password) { Ok(s) => s.into(), Err(_) => return 0 };
    if password.len() != 24 || !password.bytes().all(|c| c.is_ascii_alphanumeric()) { return 0; }
    if !hbb_common::config::Config::azsign_set_password_verified(&password) { return 0; }
    hbb_common::config::Config::set_option("verification-method".into(), "use-permanent-password".into());
    hbb_common::config::Config::set_option("approve-mode".into(), "password".into());
    1
}

#[no_mangle]
pub unsafe extern "system" fn Java_com_carriez_flutter_1hbb_AzsignRecoveryAndroid_restartTransport(
    _env: jni::JNIEnv, _class: jni::objects::JClass,
) {
    crate::rendezvous_mediator::RendezvousMediator::restart();
}
