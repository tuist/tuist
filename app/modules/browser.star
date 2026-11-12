# Locked AARs are materialized before analysis; Once consumes ordinary Android providers.
def _browser_impl(ctx):
    vendor = [path for path in walk_files(".once/vendor-browser") if path.endswith("/classes.jar") or path.endswith("/AndroidManifest.xml") or "/res/" in path]
    jars = sorted([path for path in vendor if path.endswith("/classes.jar")])
    manifests = sorted([path for path in vendor if path.endswith("/AndroidManifest.xml")])
    if not jars or not manifests:
        fail("Run python3 android/dependencies.py prepare before building TuistAppAndroid")
    sdk = host_env("ANDROID_HOME") or host_env("ANDROID_SDK_ROOT")
    if not sdk:
        fail("Set ANDROID_HOME to the installed Android SDK")
    aapt2 = sdk + "/build-tools/35.0.0/aapt2"
    android_jar = sdk + "/platforms/android-36/android.jar"
    r_jar = declare_output("browser-r.jar")
    r_txt = declare_output("R.txt")
    linked = declare_output("resources.apk")
    resources = []
    arguments = []
    for manifest in manifests:
        compiled = declare_output("resources/" + manifest.split("/")[-2] + ".zip")
        resources.append(compiled)
        arguments.extend([manifest, compiled])
    run_action(
        display_name = "Link browser SDK resource classes",
        argv = [host_which("python3"), "android/dependencies.py", "build", aapt2, android_jar, host_which("javac"), host_which("jar"), r_jar, r_txt, linked] + arguments,
        inputs = glob(ctx["srcs"]) + vendor,
        outputs = [r_jar, r_txt, linked] + resources,
        env = {"PATH": host_env("PATH"), "JAVA_HOME": host_env("JAVA_HOME")},
        toolchain_identity = host_file_sha256(aapt2) + "\x00" + host_file_sha256(android_jar) + "\x00" + host_command([host_which("javac"), "-version"]),
        identifier = "tuist_browser_resources:" + ctx["label"]["id"],
    )
    return {
        "label_id": ctx["label"]["id"],
        "transitive_compile_jars": jars + [r_jar],
        "transitive_runtime_jars": jars + [r_jar],
        "transitive_compiled_resource_zips": resources,
    }

tuist_browser = target_kind(
    docs = "Import the locked official AndroidX browser SDK and library resource classes.",
    attrs = [],
    providers = ["android_library"],
    capabilities = [capability("build", ["default"])],
    impl = _browser_impl,
)
