---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Share mobile apps, desktop apps, and command-line tools with Tuist Previews so teammates can try a build without rebuilding it locally."
}
---
# Previews {#previews}

Tuist Previews let teammates try mobile apps, desktop apps, and command-line tools without rebuilding them locally. Publish a build to your Tuist project, then share its preview link.

## What you can preview {#what-you-can-preview}

- **Mobile apps:** Android APKs and Apple application bundles or IPAs. Supported devices, simulators, and signing requirements depend on the publication workflow.
- **Desktop apps:** macOS application bundles.
- **Command-line tools:** macOS or Linux executables, on their own or bundled with their dependencies.

See <.localized_link href="/guides/features/previews/types">Supported types</.localized_link> for packaging and compatibility requirements. The artifact type determines where a preview can run; it does not dictate which build system produces it.

## Publish a preview {#publish-a-preview}

Choose your build system for setup and publication commands:

<.home_cards>
  <.home_card
    title="Xcode"
    details="Share applications from existing Xcode projects or Tuist-generated projects."
    link="/guides/features/previews/xcode"
  />
  <.home_card
    title="Gradle"
    details="Share Android apps and native command-line tools from Gradle projects."
    link="/guides/features/previews/gradle"
  />
  <.home_card
    title="Bazel"
    details="Share Android apps, Apple apps, and command-line tools with companion Bazel rules."
    link="/guides/features/previews/bazel"
  />
</.home_cards>

If you already have a supported build, use <.localized_link href="/cli/share">`tuist share`</.localized_link> to publish it without a build-system integration. Packaging and signing requirements still apply.

## Run a preview {#run-a-preview}

Recipients do not need the build system that produced the preview. Choose how to access a compatible build:

<.home_cards>
  <.home_card
    title="CLI"
    details="Run mobile apps, macOS apps, and command-line previews with tuist run."
    link="/guides/features/previews/run/cli"
  />
  <.home_card
    title="macOS app"
    details="Run compatible Apple previews through the Tuist menu bar app."
    link="/guides/features/previews/run/macos"
  />
  <.home_card
    title="iPhone app"
    details="Find and access your Apple previews on iPhone."
    link="/guides/features/previews/run/ios"
  />
</.home_cards>

## Visibility {#visibility}

Previews use the project's default visibility. Private previews require authentication and project access. Make previews public in project settings only when the build can be shared with anyone. Public visibility does not bypass platform signing or device installation requirements.

## Tracks {#tracks}

Tracks organize previews into named groups, such as `beta` for internal testers or `nightly` for automated builds. Specify a track with the publication command for your workflow; tracks are created lazily when first used. Use them to group previews by purpose and filter previews in the Tuist dashboard.

## README badge {#readme-badge}

Add a badge to your repository's `README` that points to the latest preview:

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

Replace the account and project handles with your own:

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

If the project contains multiple apps with different bundle identifiers, add a `bundle-id` query parameter to choose the app:

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```
