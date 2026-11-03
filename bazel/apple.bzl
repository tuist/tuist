"""Publish a rules_apple application through Tuist previews."""

load("@rules_apple//apple:providers.bzl", "AppleBundleInfo")
load("//private:preview.bzl", "preview_executable")

def _apple_preview_impl(ctx):
    info = ctx.attr.app[AppleBundleInfo]
    if info.product_type not in [
        "com.apple.product-type.application",
        "com.apple.product-type.application.watchapp2",
    ]:
        fail("Tuist previews require an Apple application, not a framework, extension or test")
    if info.archive.is_directory:
        fail("Tuist previews require archive output; disable experimental tree-artifact output")
    return preview_executable(ctx, info.archive, "apple", ctx.attr.app.label)

apple_preview = rule(
    implementation = _apple_preview_impl,
    executable = True,
    attrs = {
        "app": attr.label(mandatory = True, providers = [AppleBundleInfo]),
        "_sources": attr.label(default = Label("//private:sources")),
        "_runtime": attr.label(default = Label("@python_3_12//:py3_runtime"), cfg = "exec"),
    },
    doc = "Build an Apple application; publish ad-hoc simulator/macOS apps with --publish.",
)
