# The runner daemon as an Apple application dependency. An apple_application
# refuses a Rust binary dep, so this wraps one: it links nothing and leaves the
# binary at a fixed path in its output, which the app's prepackage action copies
# to Contents/MacOS/luft-runner before the bundle is signed.

def _luft_runner_apple_impl(ctx):
    binaries = [dep["binary"] for dep in ctx["deps"] if dep.get("binary")]
    if len(binaries) != 1:
        fail(ctx["label"]["id"] + ": depend on exactly one rust_binary")
    out = declare_output("luft-runner")
    copy_path(binaries[0], out)
    return {
        "label_id": ctx["label"]["id"],
        "transitive_archives": [],
        "transitive_framework_files": [out],
        "transitive_link_framework_bundles": [],
    }

luft_runner_apple = target_kind(
    docs = "The runner daemon binary, for embedding in the macOS app bundle.",
    attrs = [],
    deps = [dep("deps", ["rust_binary"], "The runner daemon binary.")],
    providers = ["apple_linkable"],
    capabilities = [capability("build", ["default"])],
    impl = _luft_runner_apple_impl,
)
