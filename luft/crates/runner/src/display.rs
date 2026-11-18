//! Sharing this machine's display: screenshots, pointer and keyboard input.
//!
//! On macOS the daemon calls CoreGraphics itself, so Screen Recording and
//! Accessibility are granted to the daemon (`luft-runner` in System
//! Settings), not to the app that installed it: launchd starts the daemon as
//! its own responsible process. Other platforms report display sharing as
//! unsupported for now.
use serde_json::Value;

/// Whether the daemon may capture the screen and post input. `None` where the
/// platform has no such permission or display sharing is unsupported.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Permissions {
    pub screen_recording: Option<bool>,
    pub accessibility: Option<bool>,
}

pub const SUPPORTED: bool = cfg!(target_os = "macos");

#[cfg(target_os = "macos")]
mod mac {
    use std::ffi::c_void;

    #[repr(C)]
    #[derive(Clone, Copy)]
    pub struct CGPoint {
        pub x: f64,
        pub y: f64,
    }

    type CFTypeRef = *const c_void;

    #[link(name = "CoreGraphics", kind = "framework")]
    unsafe extern "C" {
        pub fn CGPreflightScreenCaptureAccess() -> bool;
        pub fn CGRequestScreenCaptureAccess() -> bool;
        pub fn CGEventCreateMouseEvent(
            source: CFTypeRef,
            kind: u32,
            point: CGPoint,
            button: u32,
        ) -> CFTypeRef;
        pub fn CGEventCreateKeyboardEvent(source: CFTypeRef, key: u16, down: bool) -> CFTypeRef;
        pub fn CGEventCreateScrollWheelEvent(
            source: CFTypeRef,
            units: u32,
            count: u32,
            dy: i32,
            dx: i32,
        ) -> CFTypeRef;
        pub fn CGEventKeyboardSetUnicodeString(event: CFTypeRef, length: usize, string: *const u16);
        pub fn CGEventSetFlags(event: CFTypeRef, flags: u64);
        pub fn CGEventSetIntegerValueField(event: CFTypeRef, field: u32, value: i64);
        pub fn CGEventPost(tap: u32, event: CFTypeRef);
    }

    #[link(name = "ApplicationServices", kind = "framework")]
    unsafe extern "C" {
        pub fn AXIsProcessTrusted() -> bool;
        pub fn AXIsProcessTrustedWithOptions(options: CFTypeRef) -> bool;
        pub static kAXTrustedCheckOptionPrompt: CFTypeRef;
    }

    #[link(name = "CoreFoundation", kind = "framework")]
    unsafe extern "C" {
        pub fn CFRelease(value: CFTypeRef);
        pub fn CFDictionaryCreate(
            allocator: CFTypeRef,
            keys: *const CFTypeRef,
            values: *const CFTypeRef,
            count: isize,
            key_callbacks: *const c_void,
            value_callbacks: *const c_void,
        ) -> CFTypeRef;
        pub static kCFBooleanTrue: CFTypeRef;
        pub static kCFTypeDictionaryKeyCallBacks: c_void;
        pub static kCFTypeDictionaryValueCallBacks: c_void;
    }

    pub const HID_TAP: u32 = 0;
    pub const LEFT_DOWN: u32 = 1;
    pub const LEFT_UP: u32 = 2;
    pub const RIGHT_DOWN: u32 = 3;
    pub const RIGHT_UP: u32 = 4;
    pub const MOVED: u32 = 5;
    pub const CLICK_STATE_FIELD: u32 = 1;

    /// Posts and releases one event.
    pub fn post(event: CFTypeRef) -> Result<(), String> {
        if event.is_null() {
            return Err("Could not create the input event".into());
        }
        unsafe {
            CGEventPost(HID_TAP, event);
            CFRelease(event);
        }
        Ok(())
    }

    /// Asks macOS to list the daemon under Accessibility, showing its prompt.
    pub fn request_accessibility() {
        unsafe {
            let keys = [kAXTrustedCheckOptionPrompt];
            let values = [kCFBooleanTrue];
            let options = CFDictionaryCreate(
                std::ptr::null(),
                keys.as_ptr(),
                values.as_ptr(),
                1,
                &raw const kCFTypeDictionaryKeyCallBacks,
                &raw const kCFTypeDictionaryValueCallBacks,
            );
            if !options.is_null() {
                AXIsProcessTrustedWithOptions(options);
                CFRelease(options);
            }
        }
    }
}

pub fn permissions() -> Permissions {
    #[cfg(target_os = "macos")]
    unsafe {
        Permissions {
            screen_recording: Some(mac::CGPreflightScreenCaptureAccess()),
            accessibility: Some(mac::AXIsProcessTrusted()),
        }
    }
    #[cfg(not(target_os = "macos"))]
    Permissions::default()
}

/// Asks for whichever permission is missing. macOS shows each prompt once and
/// lists the daemon in System Settings, where the person turns it on.
pub fn request_missing() {
    #[cfg(target_os = "macos")]
    unsafe {
        if !mac::CGPreflightScreenCaptureAccess() {
            mac::CGRequestScreenCaptureAccess();
        }
        if !mac::AXIsProcessTrusted() {
            mac::request_accessibility();
        }
    }
}

/// macOS virtual key codes (ANSI layout) for the keys a thread names.
pub fn key_code(name: &str) -> Option<u16> {
    let code = match name.to_ascii_lowercase().as_str() {
        "return" | "enter" => 36,
        "tab" => 48,
        "space" => 49,
        "delete" | "backspace" => 51,
        "escape" | "esc" => 53,
        "forward_delete" => 117,
        "home" => 115,
        "end" => 119,
        "page_up" => 116,
        "page_down" => 121,
        "left" => 123,
        "right" => 124,
        "down" => 125,
        "up" => 126,
        "a" => 0,
        "s" => 1,
        "d" => 2,
        "f" => 3,
        "h" => 4,
        "g" => 5,
        "z" => 6,
        "x" => 7,
        "c" => 8,
        "v" => 9,
        "b" => 11,
        "q" => 12,
        "w" => 13,
        "e" => 14,
        "r" => 15,
        "y" => 16,
        "t" => 17,
        "1" => 18,
        "2" => 19,
        "3" => 20,
        "4" => 21,
        "6" => 22,
        "5" => 23,
        "=" => 24,
        "9" => 25,
        "7" => 26,
        "-" => 27,
        "8" => 28,
        "0" => 29,
        "]" => 30,
        "o" => 31,
        "u" => 32,
        "[" => 33,
        "i" => 34,
        "p" => 35,
        "l" => 37,
        "j" => 38,
        "'" => 39,
        "k" => 40,
        ";" => 41,
        "\\" => 42,
        "," => 43,
        "/" => 44,
        "n" => 45,
        "m" => 46,
        "." => 47,
        "`" => 50,
        _ => return None,
    };
    Some(code)
}

/// Modifier names to CGEventFlags bits.
pub fn modifier_flags(modifiers: &[String]) -> Result<u64, String> {
    modifiers.iter().try_fold(0, |flags, modifier| {
        let bit = match modifier.to_ascii_lowercase().as_str() {
            "shift" => 0x0002_0000,
            "control" | "ctrl" => 0x0004_0000,
            "option" | "alt" => 0x0008_0000,
            "command" | "cmd" => 0x0010_0000,
            other => return Err(format!("Unknown modifier {other}")),
        };
        Ok(flags | bit)
    })
}

fn number(request: &Value, key: &str) -> Result<f64, String> {
    request[key]
        .as_f64()
        .ok_or_else(|| format!("{key} must be a number"))
}

/// Runs one display operation. Points are in the main display's points, with
/// the origin at its top left, as screenshots are laid out.
pub fn perform(op: &str, request: &Value) -> Result<Value, String> {
    if !SUPPORTED {
        return Err("Display sharing is not supported on this platform yet".into());
    }
    let granted = permissions();
    let needs_input = op != "screenshot";
    if granted.screen_recording != Some(true) && !needs_input {
        return Err("Allow Screen Recording for luft-runner in System Settings".into());
    }
    if granted.accessibility != Some(true) && needs_input {
        return Err("Allow Accessibility for luft-runner in System Settings".into());
    }
    #[cfg(target_os = "macos")]
    {
        use base64::Engine;
        match op {
            "screenshot" => {
                // Requests run on their own threads, so each screenshot has its own file.
                static TAKEN: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
                let taken = TAKEN.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                let path = std::env::temp_dir()
                    .join(format!("luft-runner-{}-{taken}.png", std::process::id()));
                let status = std::process::Command::new("/usr/sbin/screencapture")
                    .args(["-x", "-t", "png"])
                    .arg(&path)
                    .status()
                    .map_err(|error| format!("Could not run screencapture: {error}"))?;
                let bytes = std::fs::read(&path);
                let _ = std::fs::remove_file(&path);
                if !status.success() {
                    return Err("screencapture failed".into());
                }
                let bytes = bytes.map_err(|error| error.to_string())?;
                Ok(
                    serde_json::json!({"mime_type":"image/png","data":base64::engine::general_purpose::STANDARD.encode(bytes)}),
                )
            }
            "mouse_move" | "click" => {
                let point = mac::CGPoint {
                    x: number(request, "x")?,
                    y: number(request, "y")?,
                };
                if op == "mouse_move" {
                    mac::post(unsafe {
                        mac::CGEventCreateMouseEvent(std::ptr::null(), mac::MOVED, point, 0)
                    })?;
                    return Ok(Value::Null);
                }
                let right = request["button"].as_str() == Some("right");
                let (down, up, button) = if right {
                    (mac::RIGHT_DOWN, mac::RIGHT_UP, 1)
                } else {
                    (mac::LEFT_DOWN, mac::LEFT_UP, 0)
                };
                let count = request["count"].as_u64().unwrap_or(1).clamp(1, 3);
                for click in 1..=count {
                    for kind in [down, up] {
                        let event = unsafe {
                            mac::CGEventCreateMouseEvent(std::ptr::null(), kind, point, button)
                        };
                        if !event.is_null() {
                            unsafe {
                                mac::CGEventSetIntegerValueField(
                                    event,
                                    mac::CLICK_STATE_FIELD,
                                    click as i64,
                                )
                            };
                        }
                        mac::post(event)?;
                    }
                }
                Ok(Value::Null)
            }
            "scroll" => {
                let dy = request["dy"].as_i64().unwrap_or(0).clamp(-10_000, 10_000) as i32;
                let dx = request["dx"].as_i64().unwrap_or(0).clamp(-10_000, 10_000) as i32;
                // Pixel units, two axes.
                mac::post(unsafe {
                    mac::CGEventCreateScrollWheelEvent(std::ptr::null(), 0, 2, dy, dx)
                })?;
                Ok(Value::Null)
            }
            "type_text" => {
                let text = request["text"].as_str().ok_or("text must be a string")?;
                // CGEventKeyboardSetUnicodeString reads at most 20 units per event.
                let units: Vec<u16> = text.encode_utf16().collect();
                for chunk in units.chunks(20) {
                    for down in [true, false] {
                        let event =
                            unsafe { mac::CGEventCreateKeyboardEvent(std::ptr::null(), 0, down) };
                        if !event.is_null() {
                            unsafe {
                                mac::CGEventKeyboardSetUnicodeString(
                                    event,
                                    chunk.len(),
                                    chunk.as_ptr(),
                                )
                            };
                        }
                        mac::post(event)?;
                    }
                }
                Ok(Value::Null)
            }
            "key" => {
                let name = request["key"].as_str().ok_or("key must be a string")?;
                let code = key_code(name).ok_or_else(|| format!("Unknown key {name}"))?;
                let modifiers: Vec<String> = request["modifiers"]
                    .as_array()
                    .map(|values| {
                        values
                            .iter()
                            .filter_map(|value| value.as_str().map(String::from))
                            .collect()
                    })
                    .unwrap_or_default();
                let flags = modifier_flags(&modifiers)?;
                for down in [true, false] {
                    let event =
                        unsafe { mac::CGEventCreateKeyboardEvent(std::ptr::null(), code, down) };
                    if !event.is_null() {
                        unsafe { mac::CGEventSetFlags(event, flags) };
                    }
                    mac::post(event)?;
                }
                Ok(Value::Null)
            }
            _ => Err(format!("Unknown display operation {op}")),
        }
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = (request, number);
        unreachable!("display sharing is unsupported off macOS")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn modifiers_combine_and_unknown_ones_fail() {
        let flags = modifier_flags(&["cmd".into(), "Shift".into()]).unwrap();
        assert_eq!(flags, 0x0010_0000 | 0x0002_0000);
        assert!(modifier_flags(&["hyper".into()]).is_err());
    }

    #[test]
    fn named_keys() {
        assert_eq!(key_code("Return"), Some(36));
        assert_eq!(
            key_code("a"),
            Some(0),
            "a is key code zero, not a missing key"
        );
        assert_eq!(key_code("f13"), None);
    }
}
