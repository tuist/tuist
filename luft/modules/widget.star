# Adapted from atlas-native/modules/widget.star, which documents why the extension
# links this way. Keep the two in step.
def _luft_widget_extension_impl(ctx):
    if host_os() != "macos":
        fail("luft_widget_extension requires macOS and Xcode")
    variant = ctx["attr"]["sdk_variant"]
    sdk = "iphonesimulator" if variant == "simulator" else "iphoneos"
    bundle_id = ctx["attr"]["bundle_id"]
    product = "LuftLiveActivity"
    if bundle_id != "dev.tuist.code.live-activity":
        fail("Expected the Luft Live Activity bundle identifier")
    sources = glob(ctx["srcs"])
    if not sources or [source for source in sources if not source.endswith(".swift")]:
        fail("luft_widget_extension requires only Swift sources, including its WidgetBundle entry point")
    templates = glob([ctx["attr"]["info_plist"]])
    if len(templates) != 1:
        fail("luft_widget_extension requires one Info.plist template")

    env = {"SWIFT_DETERMINISTIC_HASHING": "1"}
    for key in ["DEVELOPER_DIR", "TOOLCHAINS"]:
        value = host_env(key)
        if value:
            env[key] = value
    xcrun = host_which("xcrun")
    compiler = host_command([xcrun, "--sdk", sdk, "--find", "swiftc"], env = env).strip()
    linker = host_command([xcrun, "--sdk", sdk, "--find", "ld"], env = env).strip()
    sdk_path = host_command([xcrun, "--sdk", sdk, "--show-sdk-path"], env = env).strip()
    compiler_dir = compiler.rsplit("/", 1)[0]
    env["PATH"] = compiler_dir + ":" + linker.rsplit("/", 1)[0] + ":/usr/bin:/bin"
    # Include SDK interfaces and compiler overlays, not just a marketing version:
    # an Xcode replacement at the same path must not reuse the old executable.
    identity = "luft.widget.swift.v1\x00" + "\x00".join([
        compiler,
        host_command([compiler, "--version"], env = env).strip(),
        host_file_sha256(compiler),
        host_file_sha256(compiler_dir + "/swift-frontend"),
        host_file_sha256(compiler_dir + "/clang"),
        linker,
        host_file_sha256(linker),
        sdk_path,
        host_tree_sha256(sdk_path),
        host_tree_sha256(compiler_dir + "/../lib"),
    ])
    bundle = declare_output(product + ".appex")
    executable = declare_output(product + ".appex/" + product)
    info_plist = declare_output(product + ".appex/Info.plist")
    module_cache = ctx["build_dir"] + "/ModuleCache/" + content_sha256(identity)
    substitutions = {
        "LUFT_ACTIVITY_BUNDLE_ID": bundle_id,
        "LUFT_SUPPORTED_PLATFORM": "iPhoneSimulator" if variant == "simulator" else "iPhoneOS",
        "LUFT_PLATFORM_NAME": sdk,
    }
    contents = host_file_read(workspace_root() + "/" + templates[0])
    for key, value in substitutions.items():
        contents = contents.replace("$(" + key + ")", value).replace("${" + key + "}", value)
    if "$(" in contents or "${" in contents:
        fail("luft_widget_extension Info.plist contains an unresolved substitution")
    write_path(info_plist, contents)
    run_action(
        argv = [
            compiler, "-disable-sandbox", "-sdk", sdk_path,
            "-target", "arm64-apple-ios17.0" + ("-simulator" if variant == "simulator" else ""),
            "-emit-executable", "-parse-as-library", "-application-extension",
            "-module-name", product, "-module-cache-path", module_cache,
            "-framework", "Foundation",
            "-Xlinker", "-application_extension",
            "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain",
            "-Xlinker", "-rpath", "-Xlinker", "@executable_path/Frameworks",
            "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../../Frameworks",
            "-Xclang-linker", "-isysroot" + sdk_path,
            "-o", executable,
            "-framework", "UIKit", "-framework", "SwiftUI", "-framework", "WidgetKit", "-framework", "ActivityKit",
            # Keep Swift's WidgetBundle entry metadata alongside _NSExtensionMain.
            "-Xlinker", "-u", "-Xlinker", "_main",
        ] + sources,
        inputs = sources,
        outputs = [executable],
        clean_paths = [module_cache],
        create_dirs = [bundle, module_cache],
        env = env,
        toolchain_identity = identity,
        identifier = "luft_widget_compile",
        display_name = "Compile " + product,
    )
    # System extension startup and Swift's WidgetBundle entry metadata must coexist.
    # Explicitly retain main alongside the executable's NSExtensionMain entry point.
    codesign = host_command([xcrun, "--find", "codesign"], env = env).strip()
    run_action(
        argv = [codesign, "--force", "--sign", "-", "--timestamp=none", bundle],
        inputs = [executable, info_plist],
        outputs = [bundle],
        env = env,
        toolchain_identity = "luft.widget.codesign.v1\x00" + codesign + "\x00" + host_file_sha256(codesign),
        identifier = "luft_widget_sign",
        display_name = "Sign " + product + " (ad hoc)",
    )
    return {
        "label_id": ctx["label"]["id"],
        "target_kind": "apple_application",
        "application_extension": True,
        "app_path": bundle,
        "app_executable": executable,
        "app_files": [bundle],
        "bundle_id": bundle_id,
        "platform": "ios",
        "sdk_variant": variant,
        "product_name": product,
    }

luft_widget_extension = target_kind(
    docs = "Build the Swift-only Luft WidgetKit extension with its own main and an ad-hoc signed .appex.",
    attrs = [
        attr("sdk_variant", "string", required = True, configurable = False, allowed_values = ["simulator", "device"]),
        attr("bundle_id", "string", required = True, configurable = False),
        attr("info_plist", "string", required = True, configurable = False),
    ],
    providers = ["apple_application", "apple_bundle"],
    capabilities = [capability("build", ["default", "bundle"])],
    impl = _luft_widget_extension_impl,
    source_references = [source_reference(
        "Once", "apple_application",
        "https://raw.githubusercontent.com/tuist/once/0.68.2/crates/once-frontend/prelude/apple.star",
        "Use the public application provider and pre-signing script staging contract without copying the prelude.",
        content_digest = "0bfe810a3c826cd3cd106fa37fdc8574bd512c0e47d97f614e7f98aa3ef28175",
    )],
)
