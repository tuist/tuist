# NSH's release iOS SDK, which conversations embed to show the cards models
# write. Adapted from Atlas's `atlas_nsh_apple` (../atlas-native/modules/nsh.star).
# The framework hides its Rust runtime's symbols, so it links beside the Luft
# core's static library without clashes.
_NSH_VERSION = "0.5.1"
_NSH_RELEASE = "https://github.com/longbridge/nsh/releases/download/v" + _NSH_VERSION

def _nsh_apple_impl(ctx):
    sdk = ctx["attr"]["sdk"]
    out = declare_output("sdk")
    download_and_extract(
        _NSH_RELEASE + "/nsh-embed-ios.zip",
        "0a11159c9d368f7558f9b48b62ffcb956a2643ab7ddc21925404ab52dfa563a3",
        out,
    )
    variant = "ios-arm64-simulator" if sdk == "simulator" else "ios-arm64"
    triple = "arm64-apple-ios-simulator" if sdk == "simulator" else "arm64-apple-ios"
    framework = out + "/nsh-embed-ios/NativeShell.xcframework/" + variant + "/NativeShell.framework"
    binary = framework + "/NativeShell"
    module = framework + "/Modules/NativeShell.swiftmodule/" + triple
    files = [binary, framework + "/Info.plist", module + ".swiftinterface", module + ".swiftdoc"]
    return {
        "label_id": ctx["label"]["id"],
        "transitive_archives": [binary],
        "transitive_framework_files": files,
        "transitive_link_framework_bundles": [{
            "path": framework,
            "module_name": "NativeShell",
            "files": files,
            "label_id": ctx["label"]["id"],
            "linkage": "static",
            "absorbed_static_archives": [],
        }],
    }

luft_nsh_apple = target_kind(
    docs = "Checksum-pinned NSH release framework for iOS, with no development server support.",
    attrs = [attr("sdk", "string", required = True, allowed_values = ["simulator", "device"])],
    providers = ["apple_linkable"],
    capabilities = [capability("build", ["default"])],
    impl = _nsh_apple_impl,
)
