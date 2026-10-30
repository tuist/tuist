pub mod destinations;
mod ffi;
mod navigation;

pub use navigation::{GROUPS, Group, SECTIONS, Section};

#[cfg(any(target_os = "android", test))]
mod jni;
