# Tuist Previews

Share development builds of mobile apps, macOS apps, and macOS/Linux command-line tools as a link, so reviewers can run a change without checking out and building the branch.

## Problem

Trying a pull request usually means building it locally or pushing it through TestFlight or a Play Console test track, both of which add delay. Raw files sent over chat lose track of which build is which.

## How it works

You build the app or tool as usual, then `tuist share` uploads it and returns a Preview link. Recipients run compatible builds with `tuist run <url>`. The Tuist macOS menu bar app and iOS app handle compatible Apple previews; `.ipa` previews can also be installed from the device through the link. With the project connected to a Git platform, CI uploads can post Preview links on pull requests. Previews can be grouped into **tracks** (for example `beta` or `nightly`), and the optional [Tuist SDK](https://github.com/tuist/sdk) can tell testers when a newer preview exists on their track.

## Supported platforms and requirements

- **iOS**: simulator builds and device builds, from existing Xcode projects or Tuist-generated projects. Project generation is not required, but **device builds must be correctly signed by your team**; Tuist does not sign or provision them.
- **Android**: share a signed APK with `tuist share App.apk`; Android App Bundles (`.aab`) are not preview installation packages.
- **macOS apps**: share a built `.app`; signing and notarization requirements still apply.
- **Command-line tools**: share an executable on macOS or Linux, or a distribution directory with `tuist share path/to/distribution --executable bin/my-tool`. Include its resources and libraries. Recipients need a compatible OS, CPU architecture, and system dependencies.
- A Tuist account and project, and authentication on the machine or CI job that uploads.

Desktop and command-line previews need an up-to-date CLI and, for self-hosting, an updated server. They run with your user's permissions, not in a sandbox: only run builds you trust. See [supported types](/en/docs-markdown/guides/features/previews/types).

Preview visibility follows the project's default visibility unless configured otherwise. Private previews require authorized project access; public previews can be downloaded without authentication. Choose deliberately, because previews contain your app or tool.

## When it fits

Use previews for code review, design and QA checks, and internal testing of branch builds. They do not replace App Store or Play Store distribution, and tracks are not production release channels.

## How to get started

1. [Install Tuist](/en/docs-markdown/guides/install-tuist) and connect a project.
2. Build the app or tool for the intended destination.
3. Upload it as shown in the [Previews guide](/en/docs-markdown/guides/features/previews), for example `tuist share App`, `tuist share App.ipa`, or `tuist share App.apk`. Add `--track beta` to group it.
4. Share the returned link. With published Git metadata, run the latest build for a branch or commit with `tuist run App@<branch-or-sha>`.

## Pricing

Previews are listed as included in all hosted plans. Confirm on the live [pricing table](/pricing). Related: [downloads](/marketing-markdown/download) for the companion apps.
