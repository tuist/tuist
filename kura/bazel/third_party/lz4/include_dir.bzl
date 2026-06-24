"""Materialize header files into a single directory tree artifact.

rules_rs (via the hermeticbuild/rules_rust fork) cannot propagate a dependency
`-sys` crate's `cargo:include=...` path to a *dependent's* build script: the
fork's build-script runner redacts the producing crate's `OUT_DIR` to a literal
`${out_dir}` token in the cross-crate `*.depenv` file, and that token is only
resolved in the context of the build script that owns the out_dir — never in the
consuming crate's build script. So `librocksdb-sys`'s build.rs receives
`DEP_LZ4_INCLUDE=${pwd}/${out_dir}/include` verbatim and `#include <lz4.h>`
fails.

We sidestep that by turning off `lz4-sys`'s build script and feeding rocksdb's
build script a `DEP_LZ4_INCLUDE` that points at a real directory we control.
`config.include()` (cc-rs) needs a *directory*; `$(execpath)` of a header gives
a *file*. This rule copies the headers into a declared directory tree artifact,
so `$(execpath //bazel/third_party/lz4:lz4_include)` resolves to that directory.
"""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def _include_dir_impl(ctx):
    hdrs = []
    for lib in ctx.attr.libs:
        cc = lib[CcInfo].compilation_context
        hdrs += cc.direct_public_headers
        hdrs += cc.direct_private_headers
    hdrs = depset(hdrs)

    out = ctx.actions.declare_directory(ctx.attr.dir_name)
    args = ctx.actions.args()
    args.add(out.path)
    args.add_all(hdrs)
    ctx.actions.run_shell(
        inputs = hdrs,
        outputs = [out],
        command = 'set -e; dst="$1"; shift; mkdir -p "$dst"; for f in "$@"; do cp "$f" "$dst/"; done',
        arguments = [args],
        mnemonic = "MaterializeIncludeDir",
        progress_message = "Materializing include dir %{label}",
    )
    return [DefaultInfo(files = depset([out]))]

include_dir = rule(
    implementation = _include_dir_impl,
    attrs = {
        "libs": attr.label_list(
            providers = [CcInfo],
            mandatory = True,
            doc = "cc_library targets whose direct headers are copied (flattened) into the output directory.",
        ),
        "dir_name": attr.string(
            mandatory = True,
            doc = "Basename of the generated directory tree artifact.",
        ),
    },
)
