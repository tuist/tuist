---
{
  "title": "Run previews with the CLI",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Run mobile apps, macOS applications, and command-line previews with the Tuist CLI."
}
---
# Run previews with the CLI

Install the <.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link>, then run a shared preview link. You do not need the build system that produced the preview:

```bash
tuist run {url}
```

Tuist selects a compatible build for your operating system, CPU architecture, and destination. Private previews require authentication and project access.

## Mobile applications {#mobile-applications}

Select a connected device or simulator:

```bash
tuist run --device "My device" {url}
```

Android devices and emulators must be connected through ADB. You can also download the APK from the preview page and install it on an Android device that permits installation from that source. Apple builds must match the destination platform and meet their signing requirements. For an IPA, open the preview link on the destination device to install it.

## Command-line previews {#command-line-previews}

Pass arguments after `--`:

```bash
tuist run {url} -- --help
tuist run {url} -- build --configuration Release
```

Everything after `--` is forwarded literally, including `--verbose`, `--quiet`, and `--path`. Child arguments are excluded from Tuist command analytics.

The preview runs with your working directory, environment, and terminal input/output, and returns the executable's exit status. It does not replace an installed CLI or add it to `PATH`. CLI distributions remain in Tuist's local `previews` cache after execution so generated projects can continue to reference them; deleting that cache also removes those references' targets.

Desktop and CLI previews run as the current user, not in a sandbox. Only run builds from authors and pull requests you trust.

## Select a version {#select-a-version}

`tuist run` also accepts an app name with `latest`, a branch name, or a commit hash:

```bash
tuist run App@latest # Latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Latest App preview associated with a branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Preview associated with a commit
```

These selectors require the corresponding Git metadata to have been published. For workflows that omit Git metadata, use the specific preview URL instead.

For access and organization, see <.localized_link href="/guides/features/previews#visibility">visibility and tracks</.localized_link>.
