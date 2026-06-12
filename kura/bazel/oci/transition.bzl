"""Single-platform transition that mirrors oci_image_index's transition.

`oci_image_index` reaches its per-arch images through a Starlark transition that
sets `//command_line_option:platforms`. A config reached via that transition gets
an `ST-<hash>`-suffixed output directory, so its action keys differ from the same
options reached via the plain `--platforms` command-line flag (see
docs/bazel-migration-plan.md, "OCI cache fragmentation"). That means a loadable
tarball built with `--platforms` cannot reuse the binary the index already
compiled — the native arch ends up built twice.

`transitioned_image` re-exports an image through a transition that is byte-for-byte
identical in effect to oci_image_index's (same single output, same value via
`str(label)`), so the loadable image lands in the *same* `ST-` config the index
uses for that arch and shares the compiled binary instead of forcing a second
build under the flag config.
"""

def _platform_transition_impl(_settings, attr):
    return {"//command_line_option:platforms": str(attr.platform)}

_platform_transition = transition(
    implementation = _platform_transition_impl,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _transitioned_image_impl(ctx):
    return [DefaultInfo(files = depset(ctx.files.image))]

transitioned_image = rule(
    implementation = _transitioned_image_impl,
    doc = "Re-exports `image` built under a single-platform transition identical to " +
          "oci_image_index's, so a loadable tarball reuses the index's compiled binary.",
    attrs = {
        "image": attr.label(
            mandatory = True,
            allow_files = True,
            cfg = _platform_transition,
            doc = "The oci_image to build under the platform transition.",
        ),
        "platform": attr.label(
            mandatory = True,
            doc = "Target platform, set into //command_line_option:platforms by the transition.",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)
