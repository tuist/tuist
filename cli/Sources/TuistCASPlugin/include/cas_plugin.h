//===----------------------------------------------------------------------===//
//
// This header file defines the C API interface for CAS (Content Addressable Storage)
// plugins compatible with Apple's Swift Build System.
//
// This API allows third-party servers like Tuist to implement CAS functionality
// by providing the required C functions that the Swift build system expects.
//
//===----------------------------------------------------------------------===//

#ifndef CAS_PLUGIN_H
#define CAS_PLUGIN_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque types
typedef struct llcas_cas_options_s* llcas_cas_options_t;
typedef struct llcas_cas_s* llcas_cas_t;
typedef struct llcas_objectid_s llcas_objectid_t;
typedef struct llcas_digest_s llcas_digest_t;
typedef struct llcas_loaded_object_s llcas_loaded_object_t;
typedef struct llcas_object_refs_s* llcas_object_refs_t;
typedef struct llcas_cancellable_s* llcas_cancellable_t;

// Data structure for binary data
typedef struct {
    const void* data;
    size_t size;
} llcas_data_t;

// Lookup result constants
typedef enum {
    LLCAS_LOOKUP_RESULT_SUCCESS = 0,
    LLCAS_LOOKUP_RESULT_NOTFOUND = 1,
    LLCAS_LOOKUP_RESULT_ERROR = 2
} llcas_lookup_result_t;

// Required plugin API functions

// Version information
void llcas_get_plugin_version(uint32_t* major, uint32_t* minor);

// String memory management
void llcas_string_dispose(char* str);

// Cancellation support (optional)
void llcas_cancellable_cancel(llcas_cancellable_t cancellable);
void llcas_cancellable_dispose(llcas_cancellable_t cancellable);

// CAS options management
llcas_cas_options_t llcas_cas_options_create(void);
void llcas_cas_options_dispose(llcas_cas_options_t options);
void llcas_cas_options_set_client_version(llcas_cas_options_t options, uint32_t major, uint32_t minor);
void llcas_cas_options_set_ondisk_path(llcas_cas_options_t options, const char* path);
bool llcas_cas_options_set_option(llcas_cas_options_t options, const char* key, const char* value, char** error);

// CAS instance management
llcas_cas_t llcas_cas_create(llcas_cas_options_t options, char** error);
void llcas_cas_dispose(llcas_cas_t cas);

// Optional: Size management
int64_t llcas_cas_get_ondisk_size(llcas_cas_t cas, char** error);
bool llcas_cas_set_ondisk_size_limit(llcas_cas_t cas, int64_t limit, char** error);
bool llcas_cas_prune_ondisk_data(llcas_cas_t cas, char** error);

// Hash schema
const char* llcas_cas_get_hash_schema_name(llcas_cas_t cas);

// Digest operations
llcas_digest_t llcas_digest_parse(llcas_cas_t cas, const char* digest_str);
const char* llcas_digest_print(llcas_cas_t cas, llcas_digest_t digest);

// Object ID operations
llcas_objectid_t llcas_cas_get_objectid(llcas_cas_t cas, llcas_digest_t digest);
llcas_digest_t llcas_objectid_get_digest(llcas_cas_t cas, llcas_objectid_t objectid);

// Object operations
bool llcas_cas_contains_object(llcas_cas_t cas, llcas_objectid_t objectid);

// Synchronous object loading
llcas_lookup_result_t llcas_cas_load_object(llcas_cas_t cas, llcas_objectid_t objectid, llcas_loaded_object_t* object, char** error);

// Asynchronous object loading
typedef void (*llcas_load_object_callback_t)(void* context, llcas_lookup_result_t result, llcas_loaded_object_t object, char* error);
void llcas_cas_load_object_async(llcas_cas_t cas, llcas_objectid_t objectid, void* context, llcas_load_object_callback_t callback, llcas_cancellable_t* cancellable);

// Object storage
bool llcas_cas_store_object(llcas_cas_t cas, llcas_data_t data, const llcas_objectid_t* refs, size_t refs_count, llcas_objectid_t* objectid, char** error);

// Loaded object access
llcas_data_t llcas_loaded_object_get_data(llcas_cas_t cas, llcas_loaded_object_t object);
llcas_object_refs_t llcas_loaded_object_get_refs(llcas_cas_t cas, llcas_loaded_object_t object);

// Object references access
size_t llcas_object_refs_get_count(llcas_cas_t cas, llcas_object_refs_t refs);
llcas_objectid_t llcas_object_refs_get_id(llcas_cas_t cas, llcas_object_refs_t refs, size_t index);

// Action cache operations (synchronous)
llcas_lookup_result_t llcas_actioncache_get_for_digest(llcas_cas_t cas, llcas_digest_t key_digest, bool globally, llcas_objectid_t* object_id, char** error);
bool llcas_actioncache_put_for_digest(llcas_cas_t cas, llcas_digest_t key_digest, llcas_objectid_t object_id, bool globally, char** error);

// Action cache operations (asynchronous)
typedef void (*llcas_actioncache_get_callback_t)(void* context, llcas_lookup_result_t result, llcas_objectid_t object_id, char* error);
typedef void (*llcas_actioncache_put_callback_t)(void* context, bool failed, char* error);

void llcas_actioncache_get_for_digest_async(llcas_cas_t cas, llcas_digest_t key_digest, bool globally, void* context, llcas_actioncache_get_callback_t callback, llcas_cancellable_t* cancellable);
void llcas_actioncache_put_for_digest_async(llcas_cas_t cas, llcas_digest_t key_digest, llcas_objectid_t object_id, bool globally, void* context, llcas_actioncache_put_callback_t callback, llcas_cancellable_t* cancellable);

#ifdef __cplusplus
}
#endif

#endif // CAS_PLUGIN_H