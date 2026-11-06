# NSH's release SDKs are separate from the feature's Rust and CLI dependencies.
_NSH_VERSION = "0.2.0"
_NSH_RELEASE = "https://github.com/longbridge/nsh/releases/download/v" + _NSH_VERSION

def _python():
    return host_command([host_which("python3"), "-c", "import sys; print(sys.executable)"]).strip()

def _validate_cards(ctx):
    marker = declare_output("bundle-verified.json")
    python = _python()
    run_action(
        argv = [python, "cards/verify.py", "--output", marker],
        inputs = glob(["cards/App.tsx", "cards/nsh.json", "cards/bundle.json", "cards/verify.py", "cards/assets/nsh/*"]),
        outputs = [marker],
        create_dirs = [ctx["build_dir"]],
        toolchain_identity = python + "\x00" + host_command([python, "--version"]).strip(),
    )

def _nsh_apple_impl(ctx):
    _validate_cards(ctx)
    sdk = ctx["attr"]["sdk"]
    out = declare_output("sdk")
    download_and_extract(
        _NSH_RELEASE + "/nsh-embed-ios.zip",
        "846b0ed441fd072becd104c3022ff85bf1e4f79d826daf1ca5132a3ae6c56d33",
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

def _nsh_android_impl(ctx):
    _validate_cards(ctx)
    sdk = declare_output("sdk")
    aar = declare_output("aar")
    download_and_extract(
        _NSH_RELEASE + "/nsh-embed-android.zip",
        "52b886547a0ff11835c64f3d252613d33dabd6c62df3761782537aa22fe8a2af",
        sdk,
    )
    source = sdk + "/nsh-embed-android/nsh.aar"
    python = _python()
    run_action(
        argv = [python, "-m", "zipfile", "-e", source, aar],
        inputs = [source],
        outputs = [aar],
        clean_paths = [aar],
        toolchain_identity = python + "\x00" + host_command([python, "--version"]).strip(),
    )
    jar = aar + "/classes.jar"
    return {
        "label_id": ctx["label"]["id"],
        "transitive_compile_jars": [jar],
        "transitive_runtime_jars": [jar],
        "transitive_android_native_libraries": [{"abi": "arm64-v8a", "path": aar + "/jni/arm64-v8a/libnsh.so"}],
    }

atlas_nsh_apple = target_kind(
    docs = "Checksum-pinned NSH release framework, with no development server support.",
    attrs = [attr("sdk", "string", required = True, allowed_values = ["simulator", "device"])],
    providers = ["apple_linkable"],
    capabilities = [capability("build", ["default"])],
    impl = _nsh_apple_impl,
    source_references = [source_reference(
        "Once", "apple_xcframework_import",
        "https://raw.githubusercontent.com/tuist/once/0.68.2/crates/once-frontend/prelude/apple.star",
        "Expose the known release slices through the public provider contract without analysis-time downloads.",
        content_digest = "0bfe810a3c826cd3cd106fa37fdc8574bd512c0e47d97f614e7f98aa3ef28175",
    )],
)

atlas_nsh_android = target_kind(
    docs = "Checksum-pinned NSH release AAR's classes and arm64 runtime; hosts retain their API-26 text fallback.",
    providers = ["android_library"],
    capabilities = [capability("build", ["default"])],
    impl = _nsh_android_impl,
    source_references = [source_reference(
        "Once", "android_library",
        "https://raw.githubusercontent.com/tuist/once/0.68.2/crates/once-frontend/prelude/android.star",
        "Import the resource-free AAR's Java and native runtime without adding Gradle or recompiling upstream Java.",
        content_digest = "ea6c6432eeb3f140d4c06052d51630bfe2dcacf9e2b137c5d866b414067aae8d",
    )],
)
