use crate::{LoginProvider, PendingLogin, Registration, Session, begin, complete, error, restore};
use serde::Deserialize;
use serde_json::{Value, json};
use std::ffi::{CStr, CString, c_char};

#[derive(Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case")]
enum Command {
    Begin {
        server: String,
        registration: Option<Registration>,
        provider: Option<LoginProvider>,
    },
    Complete {
        pending: PendingLogin,
        callback: String,
    },
    Restore {
        session: Session,
    },
    TimeOff {
        session: Session,
        #[serde(flatten)]
        action: crate::time_off::Action,
    },
    AiAccounts {
        session: Session,
        #[serde(flatten)]
        action: crate::accounts::Action,
    },
}

pub fn execute(input: &str) -> String {
    let result = std::panic::catch_unwind(|| -> crate::Result<Value> {
        if input.len() > 1024 * 1024 {
            return Err(crate::invalid());
        }
        let command: Command = serde_json::from_str(input).map_err(|_| crate::invalid())?;
        match command {
            Command::Begin {
                server,
                registration,
                provider,
            } => serde_json::to_value(begin(&server, registration, provider)?),
            Command::Complete { pending, callback } => {
                serde_json::to_value(complete(pending, &callback)?)
            }
            Command::Restore { session } => serde_json::to_value(restore(session)?),
            Command::TimeOff { session, action } => {
                return crate::time_off::execute(session, action);
            }
            Command::AiAccounts { session, action } => {
                return crate::accounts::execute(session, action);
            }
        }
        .map_err(|_| crate::invalid())
    })
    .unwrap_or_else(|_| Err(error("internal", "Could not complete sign-in.")));
    match result {
        Ok(value) => json!({ "ok": value }).to_string(),
        Err(error) => json!({ "error": error }).to_string(),
    }
}

/// Executes on the caller's thread. Call off the UI thread.
///
/// # Safety
/// `input` must be a live NUL-terminated UTF-8 string for this call's duration.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn atlas_auth_execute(input: *const c_char) -> *mut c_char {
    let output = if input.is_null() {
        json!({"error": crate::invalid()}).to_string()
    } else {
        // SAFETY: the caller owns a valid C string for the duration of this call.
        match unsafe { CStr::from_ptr(input) }.to_str() {
            Ok(input) => execute(input),
            Err(_) => json!({"error": crate::invalid()}).to_string(),
        }
    };
    CString::new(output)
        .expect("JSON escapes NUL bytes")
        .into_raw()
}

/// # Safety
/// Pass an allocated result from `atlas_auth_execute` exactly once, or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn atlas_auth_free(output: *mut c_char) {
    if !output.is_null() {
        // SAFETY: this allocation came from CString::into_raw in atlas_auth_execute.
        drop(unsafe { CString::from_raw(output) });
    }
}

#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_tuist_atlas_AtlasAuth_execute(
    mut env: jni::JNIEnv,
    _instance: jni::objects::JObject,
    input: jni::objects::JString,
) -> jni::sys::jstring {
    let output = match env.get_string(&input) {
        Ok(input) => execute(&String::from(input)),
        Err(_) => return std::ptr::null_mut(),
    };
    env.new_string(output)
        .map_or(std::ptr::null_mut(), |value| value.into_raw())
}
