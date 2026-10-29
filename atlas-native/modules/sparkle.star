# Official release archive, including the framework's nested updater services.
_SPARKLE_VERSION = "2.10.1"
_SPARKLE_SHA256 = "1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"

def _atlas_sparkle_impl(ctx):
    archive = declare_output("Sparkle-" + _SPARKLE_VERSION + ".tar.xz")
    sdk = declare_output("sdk")
    bash = host_which("bash")
    curl = host_which("curl")
    shasum = host_which("shasum")
    tar = host_which("tar")
    ln = host_which("ln")
    # Once 0.68.2's download_and_extract accepts ZIP only. Keep fetching and
    # checksum verification in one explicit action, then extract with bsdtar.
    run_action(
        argv = [bash, "-c", "set -euo pipefail; \"$1\" --fail --location --retry 3 --proto '=https' --tlsv1.2 \"$2\" --output \"$3\"; printf '%s  %s\\n' \"$4\" \"$3\" | \"$5\" -a 256 --check", "sparkle-download", curl,
                "https://github.com/sparkle-project/Sparkle/releases/download/" + _SPARKLE_VERSION + "/Sparkle-" + _SPARKLE_VERSION + ".tar.xz", archive, _SPARKLE_SHA256, shasum],
        outputs = [archive],
        create_dirs = [ctx["build_dir"]],
        toolchain_identity = host_file_sha256(bash) + "\x00" + host_file_sha256(curl) + "\x00" + host_file_sha256(shasum),
    )
    # Once precreates the parent of a root _CodeSignature/CodeResources output.
    # Forward that path to the version signature, not an invalid root directory.
    run_action(
        argv = [bash, "-c", "set -euo pipefail; \"$1\" -xf \"$2\" -C \"$3\"; \"$4\" -s Versions/Current/_CodeSignature \"$3/Sparkle.framework/_CodeSignature\"", "sparkle-extract", tar, archive, sdk, ln],
        inputs = [archive],
        outputs = [sdk],
        clean_paths = [sdk],
        create_dirs = [sdk],
        toolchain_identity = host_file_sha256(bash) + "\x00" + host_file_sha256(tar) + "\x00" + host_file_sha256(ln),
    )
    framework = sdk + "/Sparkle.framework"
    bundle = {
        "path": framework,
        "module_name": "Sparkle",
        "files": [framework],
        "label_id": ctx["label"]["id"],
        "linkage": "dynamic",
        "absorbed_static_archives": [],
    }
    return {
        "label_id": ctx["label"]["id"],
        # A tree input retains headers, symlinks, resources and nested services.
        "transitive_framework_files": [framework],
        "transitive_link_framework_bundles": [bundle],
        "transitive_framework_bundles": [bundle],
        "transitive_linkopts": [
            "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
        ],
    }

atlas_sparkle = target_kind(
    docs = "Checksum-pinned official Sparkle macOS framework and complete embedded updater services.",
    providers = ["apple_linkable"],
    capabilities = [capability("build", ["default"])],
    impl = _atlas_sparkle_impl,
    source_references = [source_reference(
        "Once", "apple_xcframework_import and apple_application embedding",
        "https://raw.githubusercontent.com/tuist/once/0.68.2/crates/once-frontend/prelude/apple.star",
        "Use public dynamic link/runtime providers; retain the complete versioned framework tree rather than flattening nested code.",
        content_digest = "0bfe810a3c826cd3cd106fa37fdc8574bd512c0e47d97f614e7f98aa3ef28175",
    )],
)
