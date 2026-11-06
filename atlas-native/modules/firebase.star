# Once's Android prelude consumes library providers, but does not import AARs.
# All Maven bytes are materialized from the checked-in SHA-256 lock before analysis.
def _atlas_firebase_impl(ctx):
    vendor = [path for path in walk_files(".once/vendor-maven") if path.endswith("/classes.jar") or path.endswith("/AndroidManifest.xml") or "/res/" in path]
    files = glob(ctx["srcs"]) + vendor
    jars = [path for path in files if path.endswith("/classes.jar")]
    manifests = sorted([path for path in files if path.endswith("/AndroidManifest.xml") and "/vendor-maven/" in path])
    if not jars or not manifests:
        fail("Run mise run prepare:android before building AtlasAndroid")
    sdk = host_env("ANDROID_HOME") or host_env("ANDROID_SDK_ROOT")
    if not sdk:
        fail("Set ANDROID_HOME to the installed Android SDK")
    aapt2 = sdk + "/build-tools/35.0.0/aapt2"
    android_jar = sdk + "/platforms/android-35/android.jar"
    r_jar = declare_output("firebase-r.jar")
    r_txt = declare_output("R.txt")
    linked = declare_output("resources.apk")
    resources = []
    arguments = []
    for manifest in manifests:
        name = manifest.split("/")[-2]
        compiled = declare_output("resources/" + name + ".zip")
        resources.append(compiled)
        arguments.extend([manifest, compiled])
    run_action(
        display_name = "Link official Firebase SDK resource classes",
        argv = [host_which("python3"), "android/push/resources.py", "build", aapt2, android_jar, host_which("javac"), host_which("jar"), r_jar, r_txt, linked] + arguments,
        inputs = files,
        outputs = [r_jar, r_txt, linked] + resources,
        env = {"PATH": host_env("PATH"), "JAVA_HOME": host_env("JAVA_HOME")},
        toolchain_identity = host_file_sha256(aapt2) + "\x00" + host_file_sha256(android_jar) + "\x00" + host_command([host_which("javac"), "-version"]),
        identifier = "atlas_firebase_resources:" + ctx["label"]["id"],
    )
    return {
        "label_id": ctx["label"]["id"],
        "transitive_compile_jars": jars + [r_jar],
        "transitive_runtime_jars": jars + [r_jar],
        "transitive_compiled_resource_zips": resources,
    }

atlas_firebase = target_kind(
    docs = "Import the checksum-pinned official Android Firebase SDK, including library R classes.",
    attrs = [],
    providers = ["android_library"],
    capabilities = [capability("build", ["default"])],
    impl = _atlas_firebase_impl,
)
