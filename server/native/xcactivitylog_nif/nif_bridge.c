/**
 * C bridge between Erlang NIF API and the Swift xcactivitylog parser.
 *
 * This thin layer converts Erlang terms to C strings, calls the Swift
 * @_cdecl function, and converts the JSON output back to an Erlang binary.
 */

#include <erl_nif.h>
#include <string.h>
#include <stdlib.h>

/* Declared in the Swift dynamic library */
extern int parse_xcactivitylog(
    const char *path,
    const char *cas_analytics_db_path,
    const char *legacy_cas_metadata_path,
    int cache_upload_enabled,
    char **output_ptr,
    int *output_len
);

static ERL_NIF_TERM parse_nif(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    if (argc != 4) {
        return enif_make_badarg(env);
    }

    /* Get xcactivitylog path */
    ErlNifBinary path_bin;
    if (!enif_inspect_binary(env, argv[0], &path_bin)) {
        return enif_make_badarg(env);
    }

    /* Get CAS analytics database path */
    ErlNifBinary cas_db_path_bin;
    if (!enif_inspect_binary(env, argv[1], &cas_db_path_bin)) {
        return enif_make_badarg(env);
    }

    /* Get legacy CAS metadata directory path */
    ErlNifBinary legacy_cas_path_bin;
    if (!enif_inspect_binary(env, argv[2], &legacy_cas_path_bin)) {
        return enif_make_badarg(env);
    }

    /* Get cache_upload_enabled boolean */
    char atom_buf[16];
    if (!enif_get_atom(env, argv[3], atom_buf, sizeof(atom_buf), ERL_NIF_LATIN1)) {
        return enif_make_badarg(env);
    }
    int cache_upload_enabled = (strcmp(atom_buf, "true") == 0) ? 1 : 0;

    /* Null-terminate the paths */
    char *path = malloc(path_bin.size + 1);
    if (!path) return enif_make_badarg(env);
    memcpy(path, path_bin.data, path_bin.size);
    path[path_bin.size] = '\0';

    char *cas_db_path = malloc(cas_db_path_bin.size + 1);
    if (!cas_db_path) { free(path); return enif_make_badarg(env); }
    memcpy(cas_db_path, cas_db_path_bin.data, cas_db_path_bin.size);
    cas_db_path[cas_db_path_bin.size] = '\0';

    char *legacy_cas_path = malloc(legacy_cas_path_bin.size + 1);
    if (!legacy_cas_path) { free(path); free(cas_db_path); return enif_make_badarg(env); }
    memcpy(legacy_cas_path, legacy_cas_path_bin.data, legacy_cas_path_bin.size);
    legacy_cas_path[legacy_cas_path_bin.size] = '\0';

    char *output = NULL;
    int output_len = 0;

    int result = parse_xcactivitylog(path, cas_db_path, legacy_cas_path, cache_upload_enabled, &output, &output_len);

    free(path);
    free(cas_db_path);
    free(legacy_cas_path);

    if (result != 0) {
        /* Swift writes a UTF-8 error message into `output`; surface it as a
         * binary so the Elixir caller can log the actual reason instead of
         * a bare `:parse_failed` atom. Fall back to that atom only when the
         * Swift side returned no message at all (allocation failure, etc). */
        if (output != NULL && output_len > 0) {
            ERL_NIF_TERM message_binary;
            unsigned char *bin_data = enif_make_new_binary(env, output_len, &message_binary);
            memcpy(bin_data, output, output_len);
            free(output);
            return enif_make_tuple2(env, enif_make_atom(env, "error"), message_binary);
        }
        if (output) free(output);
        return enif_make_tuple2(
            env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "parse_failed")
        );
    }

    if (output == NULL) {
        return enif_make_tuple2(
            env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "parse_failed")
        );
    }

    /* Return JSON as Erlang binary */
    ERL_NIF_TERM json_binary;
    unsigned char *bin_data = enif_make_new_binary(env, output_len, &json_binary);
    memcpy(bin_data, output, output_len);
    free(output);

    return enif_make_tuple2(
        env,
        enif_make_atom(env, "ok"),
        json_binary
    );
}

static ErlNifFunc nif_funcs[] = {
    {"parse_nif", 4, parse_nif, ERL_NIF_DIRTY_JOB_CPU_BOUND}
};

ERL_NIF_INIT(Elixir.Tuist.Processor.XCActivityLogNIF, nif_funcs, NULL, NULL, NULL, NULL)
