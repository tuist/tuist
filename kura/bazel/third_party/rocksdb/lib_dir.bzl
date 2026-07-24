"""Materialize a cc_library's static archive into a single directory tree artifact.

`librocksdb-sys`'s build script takes the `ROCKSDB_LIB_DIR` env var as a *directory*
that contains `librocksdb.a`, emits `-L<dir> -lrocksdb`, and skips compiling the
bundled RocksDB C++ (see build.rs `try_to_find_and_link_lib`). `$(execpath)` of a
`cc_library` gives its `.a` file, not a directory, so this rule copies that archive
into a declared directory the build script can point at. Mirrors the sibling
`//bazel/third_party/lz4:include_dir` rule, which does the same for headers.
"""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def _lib_dir_impl(ctx):
    static = None
    for linker_input in ctx.attr.lib[CcInfo].linking_context.linker_inputs.to_list():
        for library in linker_input.libraries:
            archive = library.static_library or library.pic_static_library
            if archive and archive.basename == ctx.attr.archive_name:
                static = archive
    if static == None:
        fail("no static library named {} found in {}".format(ctx.attr.archive_name, ctx.attr.lib.label))

    out = ctx.actions.declare_directory(ctx.attr.dir_name)
    args = ctx.actions.args()
    args.add(out.path)
    args.add(static)
    args.add(ctx.attr.archive_name)
    ctx.actions.run_shell(
        inputs = [static],
        outputs = [out],
        command = 'set -e; dst="$1"; src="$2"; name="$3"; mkdir -p "$dst"; cp "$src" "$dst/$name"',
        arguments = [args],
        mnemonic = "MaterializeLibDir",
        progress_message = "Materializing lib dir %{label}",
    )
    return [DefaultInfo(files = depset([out]))]

lib_dir = rule(
    implementation = _lib_dir_impl,
    attrs = {
        "lib": attr.label(
            providers = [CcInfo],
            mandatory = True,
            doc = "cc_library whose static archive is copied into the output directory.",
        ),
        "archive_name": attr.string(
            default = "librocksdb.a",
            doc = "Basename of the static archive to extract (and the name it keeps in the dir).",
        ),
        "dir_name": attr.string(
            mandatory = True,
            doc = "Basename of the generated directory tree artifact.",
        ),
    },
)
