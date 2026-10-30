---
{
  "title": "Bazel previews",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Publish signed Android APKs and Apple simulator or macOS applications from Bazel with explicit runtime consent."
}
---
# Bazel previews

Add a companion `android_preview` or `apple_preview` target beside your application. These rules publish supported application outputs through your existing Tuist project's Previews. They consume application providers, not arbitrary build outputs or remote-cache files.

## Setup

Vendor the [`bazel/` directory from tuist/tuist](https://github.com/tuist/tuist/tree/main/bazel) at a pinned revision into `third_party/tuist_previews`. The module is not yet available in the Bazel Central Registry. Add it to `MODULE.bazel`:

```starlark
bazel_dep(name = "tuist_previews", version = "0.1.0")
local_path_override(
    module_name = "tuist_previews",
    path = "third_party/tuist_previews",
)
```

Use `rules_android` 0.8.0+ or `rules_apple` 5.3.1+, Python 3.11+, Bash, and the Tuist CLI with `tuist auth token` support (4.216.0+). Sign in with `tuist auth login` or use Tuist's existing <.localized_link href="/guides/integrations/continuous-integration">CI authentication</.localized_link>. Never put credentials in BUILD files or rule attributes. Your Tuist server must support artifact publication.

Load only the adapter you need in your `BUILD.bazel`:

```starlark
load("@tuist_previews//:android.bzl", "android_preview")

android_preview(name = "preview_android", app = ":android_app")
```

For Apple applications:

```starlark
load("@tuist_previews//:apple.bzl", "apple_preview")

apple_preview(name = "preview_ios", app = ":ios_app")
```

Keep your application's existing SDK registration, platform selection, and signing configuration.

## Build and publish

```bash
bazel run //:preview_android -- \
  --publish --project acme/app --track review
bazel run //:preview_ios --platforms=//platforms:ios_simulator -- \
  --publish --project acme/app --track review
```

Replace the application and simulator platform labels with your own. Pass `--url` for a self-hosted Tuist origin and `--revision` to associate a Git commit. Publication delegates authentication to the Tuist CLI; no separate credentials are needed.

`--publish --project account/project` authorizes this invocation only. The application must build successfully before publication runs. Without these arguments, or with `--no-publish`, the executable does not resolve credentials or contact the artifact service. Ordinary `bazel build` never publishes, including when building a preview target or replaying cached actions. `tuist bazel setup` enables caching and insights, not publication.

## Eligible applications

- **Android:** signed, non-instrumentation APKs from `ApkInfo.signed_apk`. Debug and release signatures are accepted for explicit publication. Install Android SDK build-tools (`apksigner`) and command-line tools (`apkanalyzer`), and set `ANDROID_HOME` or `ANDROID_SDK_ROOT`. Metadata comes from the APK manifest. AABs, libraries, keystores, and signing lineage are not published.
- **Apple:** ad-hoc signed simulator and macOS applications from `AppleBundleInfo.archive`, verified on macOS with `codesign --verify --deep --strict`. ZIP/IPA archives are normalized to a root `.app` ZIP while preserving executable bits and internal framework symlinks. Physical-device archives, unsigned or non-ad-hoc applications, standalone frameworks, extensions, tests, and experimental tree archives are rejected.

## Cache replay, failures, and retention

Publication runs outside cached graph execution. Identical retained payloads, metadata, target, track, and revision are confirmed by receipt without another upload or preview. A changed track or revision creates a distinct publication. Failed uploads, mismatched receipts, and unconfirmed commits exit nonzero; rerunning after an uncertain response checks the receipt before uploading again.

The receipt confirms artifact storage, not completion of asynchronous preview processing. Its link opens the project's previews list. Previews use the project's default visibility and existing distribution; the complete artifact closure stays private even in a public project.

Artifact publications expire after 30 days on hosted Tuist. Self-hosted instances use `TUIST_APP_PREVIEW_RETENTION_DAYS`; leaving it unset disables expiry for this family. Expired publication records cannot be revived by replaying the same intent.

See the <.localized_link href="/guides/features/previews">Previews overview</.localized_link> for running and sharing published applications.
