//! C ABI types mirroring llvm-c/CAS/PluginAPI_types.h (version 0.1).

#![allow(non_camel_case_types)]

use std::ffi::{c_char, c_void};

pub const LLCAS_VERSION_MAJOR: u32 = 0;
pub const LLCAS_VERSION_MINOR: u32 = 1;

pub type llcas_cas_options_t = *mut c_void;
pub type llcas_cas_t = *mut c_void;
pub type llcas_cancellable_t = *mut c_void;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct llcas_digest_t {
    pub data: *const u8,
    pub size: usize,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct llcas_data_t {
    pub data: *const c_void,
    pub size: usize,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct llcas_objectid_t {
    pub opaque: u64,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct llcas_loaded_object_t {
    pub opaque: u64,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct llcas_object_refs_t {
    pub opaque_b: u64,
    pub opaque_e: u64,
}

pub type llcas_lookup_result_t = u32;
pub const LLCAS_LOOKUP_RESULT_SUCCESS: llcas_lookup_result_t = 0;
pub const LLCAS_LOOKUP_RESULT_NOTFOUND: llcas_lookup_result_t = 1;
pub const LLCAS_LOOKUP_RESULT_ERROR: llcas_lookup_result_t = 2;

pub type llcas_cas_load_object_cb =
    unsafe extern "C" fn(*mut c_void, llcas_lookup_result_t, llcas_loaded_object_t, *mut c_char);
pub type llcas_actioncache_get_cb =
    unsafe extern "C" fn(*mut c_void, llcas_lookup_result_t, llcas_objectid_t, *mut c_char);
pub type llcas_actioncache_put_cb = unsafe extern "C" fn(*mut c_void, bool, *mut c_char);
