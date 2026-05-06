/**
 * C bridge between Erlang NIF API and the Swift xcresult parser.
 *
 * This thin layer converts Erlang terms to C strings, calls the Swift
 * @_cdecl function, and converts the JSON output back to an Erlang binary.
 */

#include <erl_nif.h>
#include <string.h>
#include <stdlib.h>

/* Declared in the Swift dynamic library */
extern int parse_xcresult(
    const char *path,
    const char *root_dir,
    char **output_ptr,
    int *output_len
);

extern int decompress_archive(
    const char *source_path,
    const char *destination_dir,
    char **error_ptr,
    int *error_len
);

static ERL_NIF_TERM parse_nif(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    if (argc != 2) {
        return enif_make_badarg(env);
    }

    /* Get xcresult path */
    ErlNifBinary path_bin;
    if (!enif_inspect_binary(env, argv[0], &path_bin)) {
        return enif_make_badarg(env);
    }

    /* Get root directory */
    ErlNifBinary root_dir_bin;
    if (!enif_inspect_binary(env, argv[1], &root_dir_bin)) {
        return enif_make_badarg(env);
    }

    /* Null-terminate the paths */
    char *path = malloc(path_bin.size + 1);
    if (!path) return enif_make_badarg(env);
    memcpy(path, path_bin.data, path_bin.size);
    path[path_bin.size] = '\0';

    char *root_dir = malloc(root_dir_bin.size + 1);
    if (!root_dir) { free(path); return enif_make_badarg(env); }
    memcpy(root_dir, root_dir_bin.data, root_dir_bin.size);
    root_dir[root_dir_bin.size] = '\0';

    char *output = NULL;
    int output_len = 0;

    int result = parse_xcresult(path, root_dir, &output, &output_len);

    free(path);
    free(root_dir);

    if (result != 0 || output == NULL) {
        if (output) free(output);
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

static ERL_NIF_TERM decompress_archive_nif(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    if (argc != 2) {
        return enif_make_badarg(env);
    }

    ErlNifBinary source_bin;
    if (!enif_inspect_binary(env, argv[0], &source_bin)) {
        return enif_make_badarg(env);
    }

    ErlNifBinary dest_bin;
    if (!enif_inspect_binary(env, argv[1], &dest_bin)) {
        return enif_make_badarg(env);
    }

    char *source = malloc(source_bin.size + 1);
    if (!source) return enif_make_badarg(env);
    memcpy(source, source_bin.data, source_bin.size);
    source[source_bin.size] = '\0';

    char *destination = malloc(dest_bin.size + 1);
    if (!destination) { free(source); return enif_make_badarg(env); }
    memcpy(destination, dest_bin.data, dest_bin.size);
    destination[dest_bin.size] = '\0';

    char *error_output = NULL;
    int error_len = 0;

    int result = decompress_archive(source, destination, &error_output, &error_len);

    free(source);
    free(destination);

    if (result == 0) {
        if (error_output) free(error_output);
        return enif_make_atom(env, "ok");
    }

    ERL_NIF_TERM reason;
    if (error_output && error_len > 0) {
        unsigned char *bin_data = enif_make_new_binary(env, error_len, &reason);
        memcpy(bin_data, error_output, error_len);
        free(error_output);
    } else {
        reason = enif_make_atom(env, "decompress_failed");
    }

    return enif_make_tuple2(env, enif_make_atom(env, "error"), reason);
}

static ErlNifFunc nif_funcs[] = {
    {"parse_nif", 2, parse_nif, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"decompress_archive_nif", 2, decompress_archive_nif, ERL_NIF_DIRTY_JOB_IO_BOUND}
};

ERL_NIF_INIT(Elixir.Tuist.Processor.XCResultNIF, nif_funcs, NULL, NULL, NULL, NULL)
