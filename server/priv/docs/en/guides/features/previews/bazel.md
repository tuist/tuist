---
{
  "title": "Bazel previews",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Publish Android apps, Apple apps, and command-line tools as previews from Bazel."
}
---
# Bazel previews

Publish Android APKs, Apple simulator and macOS apps, and command-line tools from your existing Bazel targets. Add a preview target for each output you want to share; your ordinary builds stay unchanged.

## Setup

Add [`rules_tuist` from the Tuist repository](https://github.com/tuist/tuist/tree/main/bazel) to `MODULE.bazel`, pinning the commit you want to use:

```starlark
bazel_dep(name = "rules_tuist")

git_override(
    module_name = "rules_tuist",
    remote = "https://github.com/tuist/tuist.git",
    commit = "FULL_COMMIT_SHA",
    strip_prefix = "bazel",
)
```

Keep your existing application targets, native SDKs, and signing setup. Bazel supplies the publication tools.

Sign in directly from Bazel:

```bash
bazel run @rules_tuist//:login
```

This shares credentials with the Tuist CLI and Gradle plugin; an existing sign-in works too. On CI, use `TUIST_TOKEN` or run the login target with Tuist's <.localized_link href="/guides/integrations/continuous-integration">OIDC authentication</.localized_link>. Never put credentials in BUILD files or rule attributes. Pass `-- --url https://tuist.example.com` to sign in to a self-hosted instance.

Load only the adapter you need in your `BUILD.bazel`:

```starlark
load("@rules_tuist//:android.bzl", "android_preview")

android_preview(name = "preview_android", app = ":android_app")
```

For Apple applications:

```starlark
load("@rules_tuist//:apple.bzl", "apple_preview")

apple_preview(name = "preview_ios", app = ":ios_app")
apple_preview(name = "preview_macos", app = ":macos_app")
```

For executable targets such as `cc_binary`:

```starlark
load("@rules_tuist//:executable.bzl", "executable_preview")

executable_preview(name = "preview_cli", binary = ":my_tool")
```

The executable preview includes the target's declared runtime files. Declare the libraries and resources your tool needs in its Bazel target, and use paths that work outside your build directory.

## Build and publish

```bash
bazel run //:preview_android -- \
  --publish --project acme/app --track review
bazel run //:preview_ios --platforms=//platforms:ios_simulator -- \
  --publish --project acme/app --track review
bazel run //:preview_macos -- --publish --project acme/app --track review
bazel run //:preview_cli -- --publish --project acme/app --track review
```

Replace the application and simulator platform labels with your own. Pass `--url` for a self-hosted Tuist origin and `--revision` to associate a Git commit.

Pass `--publish --project account/project` to share a successful build. Without `--publish`, or with `--no-publish`, nothing is uploaded and no sign-in is required. Ordinary `bazel build` never publishes, including on cache hits. `tuist bazel setup` enables caching and insights, not publication.

## Supported outputs

- **Android:** signed application APKs, including debug builds. Install Android SDK build-tools and command-line tools, and set `ANDROID_HOME` or `ANDROID_SDK_ROOT`. Test APKs and Android App Bundles are not supported.
- **Apple:** ad-hoc-signed simulator and macOS applications, built and verified on macOS. Physical-device builds, frameworks, extensions, and tests are not supported. Use archive output rather than experimental tree archives.
- **Command-line tools:** macOS or Linux executables for arm64 or x86_64, including universal macOS binaries. Scripts require a shebang and an interpreter on the recipient's system. Declare runtime dependencies in your target; Tuist does not install missing libraries or language runtimes.

## Cache replay, failures, and retention

Repeating the same publication reuses the existing preview without uploading it again, even when Bazel restores the build from cache. Changing the output, track, or revision creates a new publication. An upload failure fails the command; you can rerun it to check whether publication completed before trying again.

The command links to your project's previews, where processing may take a moment. Previews use the project's default visibility.

Artifact publications expire after 30 days on hosted Tuist. Self-hosted instances use `TUIST_APP_PREVIEW_RETENTION_DAYS`; leaving it unset disables expiry for this family. Expired publication records cannot be revived by replaying the same intent.

See <.localized_link href="/guides/features/previews#run-a-preview">Run a preview</.localized_link> for running published builds, access, tracks, and README badges.

## Apple previews

For Apple simulator and macOS previews, see the <.localized_link href="/guides/features/previews/run/macos">Tuist macOS companion app instructions</.localized_link>. These do not change Bazel's application eligibility or signing requirements.

## Related workflows {#publish-from-once}

Existing Once integrations have a separate <.localized_link href="/guides/features/previews/once">artifact publication guide</.localized_link>. Both workflows keep publication separate from cached graph execution.
