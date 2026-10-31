# Bazel previews

The `rules_tuist` Bzlmod module adapts application providers and executable
targets into Tuist's immutable artifact publication protocol.
It uses the same receiver and preview distribution as Once; Once itself is not
required. Application rules stay unchanged; a companion `bazel run` target is
the explicit publication boundary, like `oci_push` in `rules_oci`.

## Setup

Add the module directly from the Tuist repository to `MODULE.bazel`:

```starlark
bazel_dep(name = "rules_tuist")

git_override(
    module_name = "rules_tuist",
    remote = "https://github.com/tuist/tuist.git",
    commit = "FULL_COMMIT_SHA",
    strip_prefix = "bazel",
)
```

Replace `FULL_COMMIT_SHA` with the full commit you want to pin. Published source
archives also work with `archive_override`. See [Releases](https://github.com/tuist/tuist/blob/main/bazel/release/README.md)
for canary, RC and stable source releases and archive checksums.

The module requires modern `rules_android` (0.8.0+) / `rules_apple` (5.3.1+).
Only load the adapter for the ecosystem you use. Keep your existing application
rules, SDK registration, platform selection and signing configuration.

Add a companion executable target in your `BUILD.bazel`:

```starlark
load("@rules_tuist//:android.bzl", "android_preview")

android_preview(name = "preview_android", app = ":android_app")
```

Or, for Apple:

```starlark
load("@rules_tuist//:apple.bzl", "apple_preview")

apple_preview(name = "preview_ios", app = ":ios_app")
apple_preview(name = "preview_macos", app = ":macos_app")
```

For a command-line tool:

```starlark
load("@rules_tuist//:executable.bzl", "executable_preview")

executable_preview(name = "preview_cli", binary = ":my_tool")
```

This packages the executable and its declared runfiles in a deterministic ZIP,
including `tuist-preview.json` with the entry point, matching `tuist share`.
The archive retains the binary's relative library paths and a runfiles tree.
Declare runtime dependencies in the producing target; the rule does not bundle
undeclared system libraries or interpreters. Native Mach-O and ELF targets are
identified from their headers without executing them; scripts require a shebang
and a recipient-supplied interpreter.

Sign in directly with `bazel run @rules_tuist//:login`. Existing CLI/Gradle
credentials also work: the native publisher shares their credential files and
persistent POSIX refresh lock. On CI, set `TUIST_TOKEN` or use the login target
with Tuist's OIDC authentication. No installed Tuist CLI or host Python is
required; Bazel supplies the runtime. Do not put credentials in BUILD files or
rule attributes. Linux and macOS use their standard Bash shell.

## Build and publish

```sh
bazel run //:preview_android -- --publish --project acme/app --track review
bazel run //:preview_ios --platforms=//platforms:ios_simulator -- --publish --project acme/app --track review
bazel run //:preview_macos -- --publish --project acme/app --track review
bazel run //:preview_cli -- --publish --project acme/app --track review
```

Use your own simulator platform label for the Apple command. Pass `--url` for a
self-hosted Tuist origin and `--revision` to associate a Git commit. Project,
server, track and revision are runtime arguments, not cached build inputs.
An explicit `--publish --project account/project` authorizes **only this run**.
There is no stored authorization or repository-controlled automatic opt-in.
`--no-publish` (the default) does not resolve credentials or contact the service.
`bazel build //:preview_android` builds locally and never publishes, including on
cache hits. BEP/remote cache setup alone does not enable preview publication.

The application must build successfully before the publisher can run. The
publisher snapshots its output, verifies the native signature and constructs
the closure locally. It then checks the destination and existing receipt,
uploads missing publication content, and commits. Repeating identical payload,
metadata, target, track and revision checks the remote receipt and creates no
additional uploads or previews. Changing track or revision creates a distinct
publication. Expired receipts cannot be revived. Upload errors, mismatched
receipts and lost acknowledgments exit nonzero; the command never reports an
unconfirmed upload as success. Rerunning after an ambiguous commit checks its
receipt before attempting another upload.

Tuist creates previews asynchronously, with the project's default visibility.
The returned link opens the existing project previews list; a receipt confirms
retained artifacts, not completed preview processing. Storage, retention and
distribution are described in the [Bazel preview guide](https://tuist.dev/en/docs/guides/features/previews/bazel).

### Eligible outputs

- **Android:** `ApkInfo.signed_apk` from `android_binary`, verified using Android
  SDK `apksigner`, with package/version metadata and instrumentation declarations
  read from the APK's manifest XML using `apkanalyzer`. Install Android SDK
  build-tools and command-line tools, and set `ANDROID_HOME` (or
  `ANDROID_SDK_ROOT`). The newest stable installed tools are selected;
  `--apksigner` and `--apkanalyzer` override them. Explicit publication accepts
  verified debug or release APKs, but rejects unsigned and instrumentation APKs.
  AABs, libraries, deploy JARs, keystores and signing lineage are not exported.
- **Apple:** `AppleBundleInfo.archive` from an application rule, verified with
  macOS `codesign --verify --deep --strict`, and required to be **ad-hoc signed**.
  Simulator and macOS apps are supported, not physical-device archives,
  frameworks, extensions, tests, or experimental directory/tree archive output.
  Metadata comes from the signed bundle's Info.plist, not from filenames or
  unsigned provider binaries. IPA/ZIP layout is normalized to a root `.app` ZIP,
  preserving executable bits and internal symlinks. macOS and Xcode are required.
- **Executables:** macOS Mach-O (including universal binaries) and Linux ELF,
  arm64/x86_64, plus scripts with shebangs. Uses the executable target's
  `DefaultInfo` and declared runfiles. The producer supplies
  `dev.tuist.executable.v1` with `tuist.executable.v1` metadata (display name,
  platform, architectures and entry point); Tuist projects it into the existing
  executable preview type and distribution path. The server's CLI-preview
  rollout gate applies to this projection too.

## Validation

From the monorepo root:

```sh
python3 -m unittest discover -s bazel/tests -v
USE_BAZEL_VERSION=9.3.1 python3 bazel/tests/runtime/runtime_test.py
```

The runtime driver requires Bazel or Bazelisk and a native C++ toolchain on
`PATH`. It checks all public companion targets in directory and manifest-only runfiles modes with failing
host Python and Tuist shims. Its application providers are fixtures, not native
builds; the executable fixture is a real C++ binary with a shared library. It
publishes to a loopback receiver, reuses receipts across runfiles modes, executes
the extracted distribution outside Bazel and checks upload failures. Actual
Android/Apple builds may have their own runfiles limitations in
upstream tool rules; this check isolates the Tuist launcher from those tools.

The protocol and Apple packaging checks use native-tool and service doubles.
With `ANDROID_HOME` set and a JDK, SDK API 35/build-tools 35.0.0 and command-line
tools installed, the suite also builds and signs real manifest-only APKs to
check instrumentation rejection and quoted version metadata. Those native
regressions use authentication and receiver doubles, not live Tuist uploads.
Without the SDK/JDK the native checks are explicitly skipped.

For a real Android build, use `examples/android` with SDK API 35/build-tools
35.0.0 and Bazelisk (the example pins Bazel):

```sh
bazelisk run //:preview -- --no-publish
bazelisk run //:preview -- --publish --project acme/app --track review
```

The second command writes to the selected Tuist project. Use a disposable local
project for validation; it requires a server with the artifact receiver and
working object storage. Download the resulting APK through its preview and run
`apksigner verify` to verify the entire upload/distribution path, not only the
build. The example does not install on a device or emulator.
