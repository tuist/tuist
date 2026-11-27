use core::ffi::{c_char, c_void};

pub mod ai_subscriptions;
mod bridge;
mod client;
pub mod compose;
mod live;
mod lounges;
pub mod mcp_servers;
pub mod navigation;
mod palette;
mod presence;
pub mod prompts;
pub mod store;
pub mod theme;
mod threads;
mod updates;
pub mod workspace;
pub use bridge::{tuist_app_call, tuist_app_free};
pub use client::{Host, MobileClient, ReleaseReviews};
pub use live::{AI_SUBSCRIPTIONS, INBOX, Live};
pub use lounges::{Lounges, organizations};
pub use presence::{Presence, Socket};
pub use threads::{THREADS_UNAVAILABLE, Threads, Transport};

/// Stable destinations shared by the native frontends and GPUI navigation.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
#[repr(i32)]
pub enum Tab {
    #[default]
    Threads = 0,
    Lounges = 1,
    Dms = 2,
    Profile = 3,
    /// Collections and Releases: what the person operates, apart from their Profile.
    Ops = 4,
}

impl Tab {
    pub const ALL: [Self; 5] = [
        Self::Threads,
        Self::Lounges,
        Self::Dms,
        Self::Profile,
        Self::Ops,
    ];

    pub fn id(self) -> &'static str {
        match self {
            Self::Threads => "threads",
            Self::Lounges => "lounges",
            Self::Dms => "dms",
            Self::Profile => "profile",
            Self::Ops => "ops",
        }
    }

    pub fn from_id(id: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|tab| tab.id() == id)
    }
}

fn tab_id(index: i32) -> Option<&'static core::ffi::CStr> {
    match index {
        0 => Some(c"threads"),
        1 => Some(c"lounges"),
        2 => Some(c"dms"),
        3 => Some(c"profile"),
        4 => Some(c"ops"),
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
pub extern "system" fn Java_dev_tuist_guild_AppCore_tabCount(
    _environment: *mut c_void,
    _instance: *mut c_void,
) -> i32 {
    tuist_app_tab_count()
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_tuist_guild_AppCore_tabIdByte(
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
        assert_eq!(tuist_app_tab_count(), 5);
        // Native callers persist these numeric values; renaming a tab must not reorder them.
        assert_eq!(
            Tab::ALL.map(|tab| (tab as i32, tab.id())),
            [
                (0, "threads"),
                (1, "lounges"),
                (2, "dms"),
                (3, "profile"),
                (4, "ops")
            ]
        );
        for (index, tab) in Tab::ALL.iter().enumerate() {
            let id = tab_id(index as i32).unwrap().to_str().unwrap();
            assert_eq!(id, tab.id());
            let bytes: Vec<u8> = (0..id.len())
                .map(|offset| {
                    Java_dev_tuist_guild_AppCore_tabIdByte(
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
        assert!(tuist_app_tab_id(5).is_null());
        for (index, offset) in [(-1, 0), (5, 0), (0, -1), (0, 8)] {
            assert_eq!(
                Java_dev_tuist_guild_AppCore_tabIdByte(
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
