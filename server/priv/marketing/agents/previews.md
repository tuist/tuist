# Tuist Previews

Share development builds of iOS and Android apps as a link, so reviewers can run a change without checking out and building the branch.

## Problem

Trying a pull request usually means building it locally or pushing it through TestFlight or a Play Console test track, both of which add delay. Raw files sent over chat lose track of which build is which.

## How it works

You build the app as usual, then `tuist share` uploads it and returns a Preview link. Recipients run it with `tuist run <url>`, the Tuist macOS menu bar app (simulators and connected devices), or the Tuist iOS app; `.ipa` previews can also be installed from the device through the link. With the project connected to a Git platform, CI uploads can post Preview links on pull requests. Previews can be grouped into **tracks** (for example `beta` or `nightly`), and the optional [Tuist SDK](https://github.com/tuist/sdk) can tell testers when a newer preview exists on their track.

## Supported platforms and requirements

- **iOS**: simulator builds and device builds, from existing Xcode projects or Tuist-generated projects. Project generation is not required, but **device builds must be correctly signed by your team**; Tuist does not sign or provision them.
- **Android**: share an APK with `tuist share App.apk`.
- A Tuist account and project, and authentication on the machine or CI job that uploads.

## When it fits

Use previews for code review, design and QA checks, and internal testing of branch builds. They do not replace App Store or Play Store distribution, and tracks are not production release channels.

## How to get started

1. [Install Tuist](/en/docs-markdown/guides/install-tuist) and connect a project.
2. Build the app for the intended destination (simulator or device).
3. Upload it as shown in the [Previews guide](/en/docs-markdown/guides/features/previews), for example `tuist share App`, `tuist share App.ipa`, or `tuist share App.apk`. Add `--track beta` to group it.
4. Share the returned link. Run the latest build for a branch or commit with `tuist run App@<branch-or-sha>`.
5. In CI, make the build number (`CFBundleVersion`) unique per run; re-uploading the same binary with the same build number fails.

## Limitations

- Signing, provisioning, and device installation rules still apply; a link does not bypass them.
- Preview links are private by default: recipients need a Tuist account with access to the project. Making previews public is a project setting; choose it deliberately, because previews contain your app.
- Pull request comments require connecting the project to a supported Git platform.

## Pricing

Previews are listed as included in all hosted plans. Confirm on the live [pricing table](/pricing). Related: [downloads](/marketing-markdown/download) for the companion apps.
