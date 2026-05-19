# macOS + Xcode Image

In-house replacement for `ghcr.io/cirruslabs/macos-tahoe-xcode:N`.
A Tart VM image that bundles macOS Tahoe + a **set** of Xcode
versions + the dev tools customer iOS/macOS workflows expect.

Built by `.github/workflows/macos-xcode-image.yml` on
workflow_dispatch (we trigger it whenever Apple ships a new Xcode
and we want it in the fleet, regardless of whether Cirrus has
caught up).

Published to `ghcr.io/tuist/macos-tahoe-xcode:<major>-<minor>`,
where `<major>-<minor>` is derived from the *default* (first)
Xcode in the set — e.g. an image built with `xcode_versions=
26.5.0,26.4.1,26.3,26.2.1,26.1,26.0.1` lands at `:26-5` and has
all six Xcodes co-installed.

## Architecture: Layer 1 base for Tuist's macOS images

```
ghcr.io/cirruslabs/macos-tahoe-base:latest   <- vendor base
        ↓ + Xcodes + dev tools + WWDR certs  <- this image (Layer 1)
ghcr.io/tuist/macos-tahoe-xcode:26-5
        ↓ + runner agent + dispatch loop     <- infra/runner-image (Layer 2a)
ghcr.io/tuist/tuist-runner:macos-26-5
                                              <- shipped to customer runner Macs

ghcr.io/tuist/macos-tahoe-xcode:26-5         <- same Layer 1
        ↓ + Erlang release + launchd unit    <- infra/xcresult-processor-image (Layer 2b)
ghcr.io/tuist/tuist-xcresult-processor:<server-semver>
                                              <- runs on internal macOS fleet
```

Why split this layer out: the Xcode install is ~30 min per
version (unxip + license + runFirstLaunch + downloadAllPlatforms
on the default). If that lived in the runner-image /
xcresult-processor packer files, every `fix(runner-image): ...`
commit on main would pay the cost again. With the split, Layer 2
builds re-clone Layer 1 and lay a thin runtime on top — ~2 min
instead of ~3 hours.

## Multi-Xcode model

The image bakes in every Xcode version listed in
`xcode_versions`, newest first. The first version is the
**default**:

- `xcode-select` activates it at image-build time.
- `/usr/bin/xcrun` resolves against it.
- The major-minor `/Applications/Xcode_<major>-<minor>.app`
  symlink points at it.
- `xcodebuild -runFirstLaunch` + `-downloadAllPlatforms` run
  once against it (simulator runtimes are written to
  `/Library/Developer/CoreSimulator/Profiles/Runtimes/`, which is
  shared across every co-installed Xcode).

Co-installed older Xcodes are addressable by full path
(`/Applications/Xcode_26.0.1.app`, `/Applications/Xcode_26.4.1.app`,
etc.). Customer workflows pick a non-default Xcode the same way
they would on GitHub-hosted runners — `xcode-select`,
`DEVELOPER_DIR`, `.xcode-version` + `maxim-lobanov/setup-xcode`,
or fastlane's `xcode_select`.

This trades image size for job-time latency: pre-baking six
Xcodes adds ~200 GB to the image and ~3 hours to image-build
time, but customer workflows pinning, say, Xcode 26.0 don't pay
a ~30 min install cost on every job.

## What's in the image

- A set of Xcode bundles at `/Applications/Xcode_<version>.app`
  (one per `xcode_versions` entry) plus a
  `/Applications/Xcode_<major>-<minor>.app` symlink at the
  default for repos pinning either form in `.xcode-version`.
- iOS / tvOS / watchOS / visionOS simulator runtimes for the
  default Xcode from `xcodebuild -downloadAllPlatforms`. (Older
  co-installed Xcodes share these via CoreSimulator's system-wide
  runtime store. Workflows that need a runtime *specific* to an
  older Xcode minor — e.g. iOS 26.1 SDK against Xcode 26.1 —
  download it at job time via `xcodebuild -downloadPlatform`.)
- Dev tools via brew: `xcodes`, `xcbeautify`, `swiftformat`,
  `swiftlint`, `swiftgen`, `licenseplist`, `mint`, `carthage`,
  `fastlane`, `cocoapods`, `libimobiledevice`, `ideviceinstaller`,
  `ios-deploy`.
- Apple WWDR + Developer ID Certification Authority certificates
  in the system trust store.
- Everything the base ships: brew, mise, gh, git-lfs, jq, yq,
  node@24, rbenv (Ruby 2.7 + latest 3.x), awscli, the Tart guest
  agent, `/Users/runner` → `/Users/admin` symlink for
  GH-hosted-runner path compatibility.

The Tuist CLI is **not** preinstalled. Customer workflows install
it themselves via mise / brew so the version is theirs to pin.

## Quarterly maintenance: xcodes signin

The build workflow runs `xcodes download <version>` for each
listed Xcode on the bare-metal `vm-image-builder` Mac mini
against `developer.apple.com`. That call authenticates against
the xcodes session cached in the host's login keychain. Apple's
session lifetime is ~30 days in practice, sometimes longer —
when it expires, `xcodes download` fails non-interactively
(Apple's 2FA challenge has nowhere to answer) and the workflow
returns the auth error.

To re-mint:

1. SSH to the `vm-image-builder` Mac mini as the GitHub-Actions
   runner user.
2. Run `xcodes signin <apple-id>` and enter the password when
   prompted.
3. Approve the 2FA prompt on a trusted Apple device (phone /
   another Mac signed into the same Apple ID). Enter the 6-digit
   code at the xcodes prompt.
4. xcodes stores the session in the login keychain. Subsequent
   `xcodes download` calls run silently against Apple.

Re-run the failed workflow. xcodes' .xip cache persists across
runs, so a re-run only re-downloads versions that failed before
the session-renewal point.

The Apple ID used here is the one designated in our 1Password
vault under `Tuist macOS image-builder Apple ID`.

## Triggering a build

```
gh workflow run macos-xcode-image.yml \
  -f xcode_versions=26.5.0,26.4.1,26.3,26.2.1,26.1,26.0.1
```

The push tag is derived from the major-minor of the **first**
version: `26.5.0 → :26-5`. The remaining versions are
co-installed but don't shape the tag.

Build cost scales with the number of versions: ~30 min per Xcode
plus ~30 min for `downloadAllPlatforms` against the default,
~40 GB on disk per Xcode. The workflow timeout is set to 480 min
to cover a six-Xcode build.

To bring up multiple default-Xcode minors in parallel (e.g.
`:26-4` and `:26-5` side-by-side so the chart can hold a
profile-selectable set), trigger the workflow twice with the
two different defaults. Each lands at its own GHCR tag.

## Promoting a new Xcode to customer runners

This image is just the base layer — pushing `:26-5` doesn't
automatically roll customer runners to Xcode 26.5. To promote:

1. Trigger this workflow with the new default at the front of
   `xcode_versions`. Verify the tag appears in GHCR.
2. Bump `infra/runner-image/XCODE_VERSION` and
   `infra/xcresult-processor-image/XCODE_VERSION` to the new
   default. Commit with a `feat(runner-image): bump to Xcode
   X.Y.Z` (and a parallel `feat(xcresult-processor-image): ...`)
   message so check-releases picks it up — each file lives under
   its image's release-include-path, so a touch is what triggers
   the Layer 2 rebuild.
3. After merge, `release-runner-image` rebuilds
   `tuist-runner:macos-<major>-<minor>` against the new base and
   rewrites the chart's `runnersFleet.runnerImage` digest pin;
   `release-xcresult-processor-image` does the same on the next
   server release.
