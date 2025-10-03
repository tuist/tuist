//===----------------------------------------------------------------------===//
//
// This source file is part of the ProjectCAS project
//
// Copyright (c) 2025 Tuist GmbH
// Licensed under MIT License
//
//===----------------------------------------------------------------------===//

#ifndef PROJECT_CAS_H
#define PROJECT_CAS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define LLCAS_VERSION_MAJOR 0
#define LLCAS_VERSION_MINOR 1

typedef struct llcas_cas_options_s *llcas_cas_options_t;
typedef struct llcas_cas_s *llcas_cas_t;
typedef struct llcas_cancellable_s *llcas_cancellable_t;

/**
 * Digest hash bytes.
 */
typedef struct {
  const uint8_t *data;
  size_t size;
} llcas_digest_t;

/**
 * Data buffer for stored CAS objects.
 */
typedef struct {
  const void *data;
  size_t size;
} llcas_data_t;

/**
 * Identifier for a CAS object.
 */
typedef struct {
  uint64_t opaque;
} llcas_objectid_t;

/**
 * A loaded CAS object.
 */
typedef struct {
  uint64_t opaque;
} llcas_loaded_object_t;

/**
 * Object references for a CAS object.
 */
typedef struct {
  uint64_t opaque_b;
  uint64_t opaque_e;
} llcas_object_refs_t;

/**
 * Return values for a load operation.
 */
typedef enum {
  /**
   * The object was found.
   */
  LLCAS_LOOKUP_RESULT_SUCCESS = 0,

  /**
   * The object was not found.
   */
  LLCAS_LOOKUP_RESULT_NOTFOUND = 1,

  /**
   * An error occurred.
   */
  LLCAS_LOOKUP_RESULT_ERROR = 2,
} llcas_lookup_result_t;

/**
 * Callback for \c llcas_cas_load_object_async.
 */
typedef void (*llcas_cas_load_object_cb)(void *ctx, llcas_lookup_result_t,
                                         llcas_loaded_object_t, char *error);

/**
 * Callback for \c llcas_actioncache_get_for_digest_async.
 */
typedef void (*llcas_actioncache_get_cb)(void *ctx, llcas_lookup_result_t,
                                         llcas_objectid_t, char *error);

/**
 * Callback for \c llcas_actioncache_put_for_digest_async.
 */
typedef void (*llcas_actioncache_put_cb)(void *ctx, bool failed, char *error);

// Function declarations
void llcas_get_plugin_version(unsigned *major, unsigned *minor);
void llcas_string_dispose(char *);
void llcas_cancellable_cancel(llcas_cancellable_t);
void llcas_cancellable_dispose(llcas_cancellable_t);
llcas_cas_options_t llcas_cas_options_create(void);
void llcas_cas_options_dispose(llcas_cas_options_t);
void llcas_cas_options_set_client_version(llcas_cas_options_t, unsigned major, unsigned minor);
void llcas_cas_options_set_ondisk_path(llcas_cas_options_t, const char *path);
bool llcas_cas_options_set_option(llcas_cas_options_t, const char *name, const char *value, char **error);
llcas_cas_t llcas_cas_create(llcas_cas_options_t, char **error);
void llcas_cas_dispose(llcas_cas_t);
int64_t llcas_cas_get_ondisk_size(llcas_cas_t, char **error);
bool llcas_cas_set_ondisk_size_limit(llcas_cas_t, int64_t size_limit, char **error);
bool llcas_cas_prune_ondisk_data(llcas_cas_t, char **error);
char *llcas_cas_get_hash_schema_name(llcas_cas_t);
unsigned llcas_digest_parse(llcas_cas_t, const char *printed_digest, uint8_t *bytes, size_t bytes_size, char **error);
bool llcas_digest_print(llcas_cas_t, llcas_digest_t, char **printed_id, char **error);
bool llcas_cas_get_objectid(llcas_cas_t, llcas_digest_t digest, llcas_objectid_t *p_id, char **error);
llcas_digest_t llcas_objectid_get_digest(llcas_cas_t, llcas_objectid_t);
llcas_lookup_result_t llcas_cas_contains_object(llcas_cas_t, llcas_objectid_t, bool globally, char **error);
llcas_lookup_result_t llcas_cas_load_object(llcas_cas_t, llcas_objectid_t, llcas_loaded_object_t *, char **error);
void llcas_cas_load_object_async(llcas_cas_t, llcas_objectid_t, void *ctx_cb, llcas_cas_load_object_cb, llcas_cancellable_t *cancel_tok);
bool llcas_cas_store_object(llcas_cas_t, llcas_data_t, const llcas_objectid_t *refs, size_t refs_count, llcas_objectid_t *p_id, char **error);
llcas_data_t llcas_loaded_object_get_data(llcas_cas_t, llcas_loaded_object_t);
llcas_object_refs_t llcas_loaded_object_get_refs(llcas_cas_t, llcas_loaded_object_t);
size_t llcas_object_refs_get_count(llcas_cas_t, llcas_object_refs_t);
llcas_objectid_t llcas_object_refs_get_id(llcas_cas_t, llcas_object_refs_t, size_t index);
llcas_lookup_result_t llcas_actioncache_get_for_digest(llcas_cas_t, llcas_digest_t key, llcas_objectid_t *p_value, bool globally, char **error);
void llcas_actioncache_get_for_digest_async(llcas_cas_t, llcas_digest_t key, bool globally, void *ctx_cb, llcas_actioncache_get_cb, llcas_cancellable_t *cancel_tok);
bool llcas_actioncache_put_for_digest(llcas_cas_t, llcas_digest_t key, llcas_objectid_t value, bool globally, char **error);
void llcas_actioncache_put_for_digest_async(llcas_cas_t, llcas_digest_t key, llcas_objectid_t value, bool globally, void *ctx_cb, llcas_actioncache_put_cb, llcas_cancellable_t *cancel_tok);

#endif /* PROJECT_CAS_PLUGIN_H */