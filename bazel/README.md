# Bazel application previews

The `tuist_previews` Bzlmod module adapts **application providers**, not filenames
or remote-cache contents, into Tuist's immutable artifact publication protocol.
It uses the same receiver and preview distribution as Once; Once itself is not
required. This module is not yet registered in the Bazel Central Registry.

## Setup

Vendor this directory from a pinned `tuist/tuist` revision into
`third_party/tuist_previews`, then add to your `MODULE.bazel`:

```starlark
bazel_dep(name = "tuist_previews", version = "0.1.0")
local_path_override(
    module_name = "tuist_previews",
    path = "third_party/tuist_previews",
)
```

The module requires modern `rules_android` (0.8.0+) / `rules_apple` (5.3.1+).
Only load the adapter for the ecosystem you use. Keep your existing application
rules, SDK registration, platform selection and signing configuration.

Add a companion executable target in your `BUILD.bazel`:

```starlark
load("@tuist_previews//:android.bzl", "android_preview")

android_preview(name = "preview_android", app = ":android_app")
```

Or, for Apple:

```starlark
load("@tuist_previews//:apple.bzl", "apple_preview")

apple_preview(name = "preview_ios", app = ":ios_app")
```

Install Python 3.11+, Bash, and the Tuist CLI with `tuist auth token` support
(4.216.0+). Sign in with `tuist auth login` or configure Tuist's existing CI
authentication. The publisher delegates token resolution/refresh to that CLI;
do not put credentials in BUILD files, rule attributes, or command-line flags.

## Build and publish

```sh
bazel run //:preview_android -- --publish --project acme/app --track review
bazel run //:preview_ios --platforms=//platforms:ios_simulator -- --publish --project acme/app --track review
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
distribution are described in the [Bazel preview guide](../server/priv/docs/en/guides/features/previews/bazel.md).

### Eligible applications

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

## Validation

From the monorepo root:

```sh
python3 -m unittest discover -s bazel/tests -v
```

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
