use crate::{Host, MobileClient};
use serde_json::Value;
use std::ffi::{CStr, CString, c_char, c_void};
use std::sync::{Mutex, OnceLock};

static CLIENT: OnceLock<Mutex<MobileClient>> = OnceLock::new();
const FAILURE: &str = r#"{"view":{"profiles":[],"active_profile_id":null,"generation":0,"navigation":{"tab":"threads","thread_id":null,"path":"/threads","revision":0}},"data":null,"error":"Native bridge failed"}"#;

fn serialized(input: &str, host: &mut dyn Host) -> String {
    match CLIENT
        .get_or_init(|| Mutex::new(MobileClient::new()))
        .lock()
    {
        Ok(mut client) => client.call(input, host),
        Err(_) => FAILURE.into(),
    }
}

type Callback = unsafe extern "C" fn(*const c_char, *mut c_void) -> *mut c_char;
struct CHost {
    callback: Callback,
    context: *mut c_void,
}

impl Host for CHost {
    fn perform(&mut self, action: Value) -> Result<Value, String> {
        let input = CString::new(action.to_string()).map_err(|_| "Invalid action")?;
        // The host retains this pointer until its next callback; copy it immediately.
        let output = unsafe { (self.callback)(input.as_ptr(), self.context) };
        if output.is_null() {
            return Err("Native callback failed".into());
        }
        let output = unsafe { CStr::from_ptr(output) }
            .to_str()
            .map_err(|_| "Invalid host response")?;
        serde_json::from_str(output).map_err(|_| "Invalid host response".into())
    }
}

/// # Safety
/// Input and host result must be valid NUL-terminated UTF-8 strings. The host
/// must not reenter this ABI and retains ownership of its response pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tuist_app_call(
    input: *const c_char,
    host: Option<Callback>,
    context: *mut c_void,
) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        if input.is_null() {
            return FAILURE.into();
        }
        let Ok(input) = (unsafe { CStr::from_ptr(input) }).to_str() else {
            return FAILURE.into();
        };
        let Some(callback) = host else {
            return FAILURE.into();
        };
        serialized(input, &mut CHost { callback, context })
    })
    .unwrap_or_else(|_| FAILURE.into());
    CString::new(result).unwrap_or_default().into_raw()
}

/// Runs `compose` (see the README) without taking the client's lock, so the
/// composer never waits behind a network operation. Free the result with
/// `tuist_app_free`.
///
/// # Safety
/// Input must be null or a valid NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tuist_app_compose(input: *const c_char) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        let input = if input.is_null() {
            ""
        } else {
            unsafe { CStr::from_ptr(input) }.to_str().unwrap_or("")
        };
        let value: Value = serde_json::from_str(input).unwrap_or(Value::Null);
        crate::compose::compose(&value).to_string()
    })
    .unwrap_or_else(|_| "{}".into());
    CString::new(result).unwrap_or_default().into_raw()
}

/// # Safety
/// The pointer must be null or returned by `tuist_app_call`, and freed only once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tuist_app_free(value: *mut c_char) {
    if !value.is_null() {
        drop(unsafe { CString::from_raw(value) });
    }
}

#[cfg(any(target_os = "android", test))]
mod android {
    use super::*;
    use jni::{
        JNIEnv,
        objects::{JObject, JString, JValue},
        sys::jstring,
    };

    struct JavaHost<'a, 'b, 'c> {
        env: &'a mut JNIEnv<'b>,
        host: JObject<'c>,
    }
    impl Host for JavaHost<'_, '_, '_> {
        fn perform(&mut self, action: Value) -> Result<Value, String> {
            let result = (|| -> jni::errors::Result<String> {
                let input = self.env.new_string(action.to_string())?;
                let object = self
                    .env
                    .call_method(
                        &self.host,
                        "perform",
                        "(Ljava/lang/String;)Ljava/lang/String;",
                        &[JValue::Object(input.as_ref())],
                    )?
                    .l()?;
                let output = JString::from(object);
                let text: String = self.env.get_string(&output)?.into();
                self.env.delete_local_ref(output)?;
                self.env.delete_local_ref(input)?;
                Ok(text)
            })();
            if self.env.exception_check().unwrap_or(false) {
                let _ = self.env.exception_clear();
            }
            let text = result.map_err(|_| "Native callback failed")?;
            serde_json::from_str(&text).map_err(|_| "Invalid native response".into())
        }
    }

    /// Noora's semantic colors as the JSON `tuist_app_theme` returns.
    #[unsafe(no_mangle)]
    pub extern "system" fn Java_dev_tuist_guild_AppCore_theme(
        env: JNIEnv,
        _instance: JObject,
    ) -> jstring {
        env.new_string(crate::theme::json().to_str().unwrap_or("{}"))
            .map(JString::into_raw)
            .unwrap_or(std::ptr::null_mut())
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_dev_tuist_guild_AppCore_compose(
        mut env: JNIEnv,
        _instance: JObject,
        input: JString,
    ) -> jstring {
        let input: String = env.get_string(&input).map(Into::into).unwrap_or_default();
        let value: Value = serde_json::from_str(&input).unwrap_or(Value::Null);
        env.new_string(crate::compose::compose(&value).to_string())
            .map(JString::into_raw)
            .unwrap_or(std::ptr::null_mut())
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_dev_tuist_guild_AppCore_request(
        mut env: JNIEnv,
        _instance: JObject,
        input: JString,
        host: JObject,
    ) -> jstring {
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let input: String = env.get_string(&input).map_err(|_| ())?.into();
            Ok::<_, ()>(serialized(
                &input,
                &mut JavaHost {
                    env: &mut env,
                    host,
                },
            ))
        }))
        .ok()
        .and_then(std::result::Result::ok)
        .unwrap_or_else(|| FAILURE.into());
        if env.exception_check().unwrap_or(false) {
            let _ = env.exception_clear();
        }
        env.new_string(result)
            .map(JString::into_raw)
            .unwrap_or(std::ptr::null_mut())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn c_ownership_and_null_arguments() {
        let output = unsafe { tuist_app_call(std::ptr::null(), None, std::ptr::null_mut()) };
        let value: Value =
            serde_json::from_str(unsafe { CStr::from_ptr(output) }.to_str().unwrap()).unwrap();
        assert!(value["error"].is_string());
        unsafe {
            tuist_app_free(output);
            tuist_app_free(std::ptr::null_mut());
        }
    }
}
