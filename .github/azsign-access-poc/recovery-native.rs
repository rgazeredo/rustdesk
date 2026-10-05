#[no_mangle]
pub unsafe extern "system" fn Java_com_carriez_flutter_1hbb_AzsignRecoveryAndroid_deviceId(
    env: jni::JNIEnv, _class: jni::objects::JClass,
) -> jni::sys::jstring {
    env.new_string(hbb_common::config::Config::get_id()).map(|s| s.into_raw()).unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "system" fn Java_com_carriez_flutter_1hbb_AzsignRecoveryAndroid_applyPassword(
    mut env: jni::JNIEnv, _class: jni::objects::JClass, password: jni::objects::JString,
) -> jni::sys::jboolean {
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
