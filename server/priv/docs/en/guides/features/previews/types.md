---
{
  "title": "Supported preview types",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Packaging and compatibility requirements for mobile apps, macOS apps, and command-line previews."
}
---
# Supported preview types

The preview type determines what you package and where it can run, independently of the build system that produces it. Each publication workflow has its own signing and eligibility requirements.

## Mobile apps {#mobile-apps}

- **Android:** a signed application APK. Recipients need a compatible Android device or emulator. Android App Bundles (`.aab`) are not preview installation packages.
- **Apple:** an application bundle for a simulator, or an exported IPA for physical devices. Device builds need a provisioning profile that permits installation on the recipient's device.

The <.localized_link href="/guides/features/previews/xcode">Xcode</.localized_link>, <.localized_link href="/guides/features/previews/gradle">Gradle</.localized_link>, and <.localized_link href="/guides/features/previews/bazel">Bazel</.localized_link> guides describe which outputs each workflow can publish. For example, Bazel and Once publication support eligible Apple simulator and macOS applications, not physical-device builds.

## Desktop apps {#desktop-apps}

Share a built macOS application bundle:

```bash
tuist share path/to/MyApp.app
```

Signing and notarization requirements still apply. A desktop application bundle is different from the Tuist macOS app, which recipients can use to run previews.

## Command-line tools {#command-line-tools}

Share a standalone executable on macOS or Linux:

```bash
tuist share path/to/my-tool
```

If the CLI needs resource bundles, dynamic libraries, or helper executables, assemble a distribution directory and specify its entry point relative to that directory:

```bash
tuist share path/to/distribution --executable bin/my-tool
```

The entire distribution directory is uploaded. Include the libraries, resources, and helpers your tool needs, and make sure it can run outside your build directory. Scripts need a shebang and an interpreter installed on the recipient's system.

## Multiple CLI targets {#multiple-cli-targets}

A preview groups builds of the same CLI for one commit; each build contains a distribution for one operating system and one or more CPU architectures. For example, one preview can contain macOS arm64, macOS x86_64, and Linux x86_64 distributions. A universal macOS executable covers both Mac architectures in one build.

Build each target separately, then publish the distributions sequentially from the same Git checkout using the same entry-point basename and track:

```bash
tuist share dist/macos-arm64 --executable bin/tuist --track pr
tuist share dist/macos-x86_64 --executable bin/tuist --track pr
tuist share dist/linux-x86_64 --executable bin/tuist --track pr
```

These uploads add builds to the same preview link. Keep the project, commit, publishing account, CLI name, and track identical across uploads. Tuist selects the build that matches the recipient's operating system and CPU architecture.

## Client and server compatibility {#client-and-server-compatibility}

Use an up-to-date Tuist CLI to run desktop and command-line previews. If you self-host Tuist, update your server before publishing these types. Mobile previews continue to work with older clients.

Build for your recipients' operating systems and CPU architectures. Tuist does not cross-compile your app or install its dependencies; Linux tools also need compatible system libraries.

Previews run with your user account's permissions, not in a sandbox. Only run builds from authors and pull requests you trust.

See <.localized_link href="/guides/features/previews/run/cli">Run previews with the CLI</.localized_link> for execution behavior and argument forwarding, and the <.localized_link href="/guides/features/previews#visibility">preview overview</.localized_link> for access, tracks, and README badges.
