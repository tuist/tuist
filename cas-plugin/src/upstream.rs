//! Dynamically loaded function table for the wrapped upstream CAS plugin
//! (Xcode's libToolchainCASPlugin).

use std::ffi::{c_char, c_void};

use crate::types::*;

macro_rules! upstream_table {
    (
        required: { $( $name:ident : fn( $($arg:ty),* ) -> $ret:ty ),+ $(,)? }
        optional: { $( $opt_name:ident : fn( $($opt_arg:ty),* ) -> $opt_ret:ty ),+ $(,)? }
    ) => {
        // Some table entries exist for ABI completeness rather than current
        // call sites (e.g. upstream async variants, answered synchronously).
        #[allow(dead_code)]
        pub struct Upstream {
            _lib: libloading::Library,
            $( pub $name: unsafe extern "C" fn($($arg),*) -> $ret, )+
            $( pub $opt_name: Option<unsafe extern "C" fn($($opt_arg),*) -> $opt_ret>, )+
        }

        impl Upstream {
            pub unsafe fn load(path: &str) -> Result<Self, String> {
                let lib = libloading::Library::new(path)
                    .map_err(|e| format!("tuist-cas-plugin: failed to load upstream plugin at {path}: {e}"))?;
                $(
                    let $name = *lib
                        .get::<unsafe extern "C" fn($($arg),*) -> $ret>(concat!(stringify!($name), "\0").as_bytes())
                        .map_err(|e| format!("tuist-cas-plugin: missing symbol {}: {e}", stringify!($name)))?;
                )+
                $(
                    let $opt_name = lib
                        .get::<unsafe extern "C" fn($($opt_arg),*) -> $opt_ret>(concat!(stringify!($opt_name), "\0").as_bytes())
                        .map(|s| *s)
                        .ok();
                )+
                Ok(Self { _lib: lib, $( $name, )+ $( $opt_name, )+ })
            }
        }
    };
}

upstream_table! {
    required: {
        llcas_get_plugin_version: fn(*mut u32, *mut u32) -> (),
        llcas_string_dispose: fn(*mut c_char) -> (),
        llcas_cas_options_create: fn() -> llcas_cas_options_t,
        llcas_cas_options_dispose: fn(llcas_cas_options_t) -> (),
        llcas_cas_options_set_client_version: fn(llcas_cas_options_t, u32, u32) -> (),
        llcas_cas_options_set_ondisk_path: fn(llcas_cas_options_t, *const c_char) -> (),
        llcas_cas_options_set_option: fn(llcas_cas_options_t, *const c_char, *const c_char, *mut *mut c_char) -> bool,
        llcas_cas_create: fn(llcas_cas_options_t, *mut *mut c_char) -> llcas_cas_t,
        llcas_cas_dispose: fn(llcas_cas_t) -> (),
        llcas_cas_get_hash_schema_name: fn(llcas_cas_t) -> *mut c_char,
        llcas_digest_parse: fn(llcas_cas_t, *const c_char, *mut u8, usize, *mut *mut c_char) -> u32,
        llcas_digest_print: fn(llcas_cas_t, llcas_digest_t, *mut *mut c_char, *mut *mut c_char) -> bool,
        llcas_cas_get_objectid: fn(llcas_cas_t, llcas_digest_t, *mut llcas_objectid_t, *mut *mut c_char) -> bool,
        llcas_objectid_get_digest: fn(llcas_cas_t, llcas_objectid_t) -> llcas_digest_t,
        llcas_cas_contains_object: fn(llcas_cas_t, llcas_objectid_t, bool, *mut *mut c_char) -> llcas_lookup_result_t,
        llcas_cas_load_object: fn(llcas_cas_t, llcas_objectid_t, *mut llcas_loaded_object_t, *mut *mut c_char) -> llcas_lookup_result_t,
        llcas_cas_load_object_async: fn(llcas_cas_t, llcas_objectid_t, *mut c_void, llcas_cas_load_object_cb, *mut llcas_cancellable_t) -> (),
        llcas_cas_store_object: fn(llcas_cas_t, llcas_data_t, *const llcas_objectid_t, usize, *mut llcas_objectid_t, *mut *mut c_char) -> bool,
        llcas_loaded_object_get_data: fn(llcas_cas_t, llcas_loaded_object_t) -> llcas_data_t,
        llcas_loaded_object_get_refs: fn(llcas_cas_t, llcas_loaded_object_t) -> llcas_object_refs_t,
        llcas_object_refs_get_count: fn(llcas_cas_t, llcas_object_refs_t) -> usize,
        llcas_object_refs_get_id: fn(llcas_cas_t, llcas_object_refs_t, usize) -> llcas_objectid_t,
        llcas_actioncache_get_for_digest: fn(llcas_cas_t, llcas_digest_t, *mut llcas_objectid_t, bool, *mut *mut c_char) -> llcas_lookup_result_t,
        llcas_actioncache_get_for_digest_async: fn(llcas_cas_t, llcas_digest_t, bool, *mut c_void, llcas_actioncache_get_cb, *mut llcas_cancellable_t) -> (),
        llcas_actioncache_put_for_digest: fn(llcas_cas_t, llcas_digest_t, llcas_objectid_t, bool, *mut *mut c_char) -> bool,
        llcas_actioncache_put_for_digest_async: fn(llcas_cas_t, llcas_digest_t, llcas_objectid_t, bool, *mut c_void, llcas_actioncache_put_cb, *mut llcas_cancellable_t) -> (),
    }
    optional: {
        llcas_cancellable_cancel: fn(llcas_cancellable_t) -> (),
        llcas_cancellable_dispose: fn(llcas_cancellable_t) -> (),
        llcas_cas_get_ondisk_size: fn(llcas_cas_t, *mut *mut c_char) -> i64,
        llcas_cas_set_ondisk_size_limit: fn(llcas_cas_t, i64, *mut *mut c_char) -> bool,
        llcas_cas_prune_ondisk_data: fn(llcas_cas_t, *mut *mut c_char) -> bool,
        llcas_cas_store_from_filepath: fn(llcas_cas_t, *const c_char, *mut llcas_objectid_t, *mut *mut c_char) -> bool,
        llcas_loaded_object_export_data_to_filepath: fn(llcas_cas_t, llcas_loaded_object_t, *const c_char, *mut *mut c_char) -> bool,
    }
}
