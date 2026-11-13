use core::ffi::{c_char, c_void};

mod bridge;
mod client;
pub use bridge::{tuist_app_call, tuist_app_free};
pub use client::{Host, MobileClient};

/// Stable destinations shared by the native frontends and GPUI navigation.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
#[repr(i32)]
pub enum Tab {
    #[default]
    Previews = 0,
    Profile = 1,
}

impl Tab {
    pub const ALL: [Self; 2] = [Self::Previews, Self::Profile];

    pub fn id(self) -> &'static str {
        match self {
            Self::Previews => "previews",
            Self::Profile => "profile",
        }
    }
}

fn tab_id(index: i32) -> Option<&'static core::ffi::CStr> {
    match index {
        0 => Some(c"previews"),
        1 => Some(c"profile"),
        _ => None,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn tuist_app_tab_count() -> i32 {
    Tab::ALL.len() as i32
}

/// The returned string is immutable and lives for the process lifetime.
#[unsafe(no_mangle)]
pub extern "C" fn tuist_app_tab_id(index: i32) -> *const c_char {
    tab_id(index).map_or(core::ptr::null(), |value| value.as_ptr())
}

// Primitive-only JNI keeps this catalog independent of Java heap ownership.
#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_tuist_code_AppCore_tabCount(
    _environment: *mut c_void,
    _instance: *mut c_void,
) -> i32 {
    tuist_app_tab_count()
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_tuist_code_AppCore_tabIdByte(
    _environment: *mut c_void,
    _instance: *mut c_void,
    index: i32,
    offset: i32,
) -> i32 {
    let Ok(offset) = usize::try_from(offset) else {
        return -1;
    };
    tab_id(index)
        .and_then(|value| value.to_bytes().get(offset))
        .map_or(-1, |value| i32::from(*value))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn native_frontends_share_the_navigation_catalog() {
        assert_eq!(tuist_app_tab_count(), 2);
        for (index, tab) in Tab::ALL.iter().enumerate() {
            let id = tab_id(index as i32).unwrap().to_str().unwrap();
            assert_eq!(id, tab.id());
            let bytes: Vec<u8> = (0..id.len())
                .map(|offset| {
                    Java_dev_tuist_code_AppCore_tabIdByte(
                        core::ptr::null_mut(),
                        core::ptr::null_mut(),
                        index as i32,
                        offset as i32,
                    ) as u8
                })
                .collect();
            assert_eq!(bytes, id.as_bytes());
        }
        assert!(tuist_app_tab_id(-1).is_null());
        assert!(tuist_app_tab_id(2).is_null());
        for (index, offset) in [(-1, 0), (2, 0), (0, -1), (0, 8)] {
            assert_eq!(
                Java_dev_tuist_code_AppCore_tabIdByte(
                    core::ptr::null_mut(),
                    core::ptr::null_mut(),
                    index,
                    offset,
                ),
                -1
            );
        }
    }
}
