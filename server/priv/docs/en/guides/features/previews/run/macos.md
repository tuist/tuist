---
{
  "title": "Run previews with the macOS app",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Use the Tuist macOS menu bar app to run compatible Apple previews on devices and simulators."
}
---
# Run previews with the macOS app

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download Tuist for macOS</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

For Apple previews, the Tuist macOS menu bar app is an alternative to the CLI, whether the build came from Xcode, Bazel, or Once. The publication workflow's signing and eligibility requirements still apply.

## Install {#install}

[Download the app](https://tuist.dev/download) or install it with `brew install --cask tuist/tuist/tuist`.

## Run a build {#run-a-build}

Select a compatible device or simulator in the menu bar app, then click **Run** on a preview page.

The macOS app first requests the latest compatible preview per app. On older servers that select distinct apps before applying platform filters, it falls back to paginated history without imposing a cutoff that could hide an available build.

For access and organization, see <.localized_link href="/guides/features/previews#visibility">visibility and tracks</.localized_link>.
