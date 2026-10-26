# Once 0.68.2's Swift driver uses --sysroot. Darwin Clang needs -isysroot
# to read SDKSettings.json and stamp the SDK rather than the deployment minimum.
def _atlas_apple_sdk_impl(ctx):
    sdk = ctx["attr"]["sdk"]
    path = host_command([host_which("xcrun"), "--sdk", sdk, "--show-sdk-path"]).strip()
    return {
        "label_id": ctx["label"]["id"],
        # Joined spelling keeps this pair intact through linkopts deduplication.
        "transitive_linkopts": ["-Xclang-linker", "-isysroot" + path],
    }

atlas_apple_sdk = target_kind(
    docs = "Forward the selected iOS SDK to Darwin Clang without raising the deployment minimum.",
    attrs = [attr("sdk", "string", required = True, configurable = False, allowed_values = ["iphoneos", "iphonesimulator"])],
    providers = ["apple_linkable"],
    capabilities = [capability("build", ["default"])],
    impl = _atlas_apple_sdk_impl,
)
