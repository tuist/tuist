# macOS + Xcode Image

In-house replacement for `ghcr.io/cirruslabs/macos-tahoe-xcode:N`.
A Tart VM image that bundles macOS Tahoe + a specific Xcode +
the dev tools customer iOS/macOS workflows expect.

Built by `.github/workflows/macos-xcode-image.yml` on
workflow_dispatch (we trigger it whenever Apple ships a new Xcode
and we want it in the fleet, regardless of whether Cirrus has
caught up).

Published to `ghcr.io/tuist/macos-tahoe-xcode:<major>-<minor>`
(e.g. `:26-4` for Xcode 26.4.x). The tag is major-minor, not the
patch version, so a 26.4.0 → 26.4.1 Apple bump replaces the image
under the same tag without touching downstream packer files.

## Architecture: Layer 1 base for Tuist's macOS images

```
ghcr.io/cirruslabs/macos-tahoe-base:latest   <- vendor base
        ↓ + Xcode + dev tools + WWDR certs   <- this image (Layer 1)
ghcr.io/tuist/macos-tahoe-xcode:26-4
        ↓ + runner agent + dispatch loop     <- infra/runner-image (Layer 2a)
ghcr.io/tuist/tuist-runner:macos-26-4
                                              <- shipped to customer runner Macs

ghcr.io/tuist/macos-tahoe-xcode:26-4         <- same Layer 1
        ↓ + Erlang release + launchd unit    <- infra/xcresult-processor-image (Layer 2b)
ghcr.io/tuist/tuist-xcresult-processor:<server-semver>
                                              <- runs on internal macOS fleet
```

Why split this layer out: the Xcode install is ~30 min of work
(unxip, license accept, runFirstLaunch, downloadAllPlatforms). If
that lived in the runner-image / xcresult-processor packer files,
every `fix(runner-image): ...` commit on main would pay the cost
again. With the split, Layer 2 builds re-clone Layer 1 and lay
a thin runtime on top — ~2 min instead of ~30.

## What's in the image

- Full Xcode at `/Applications/Xcode_<version>.app` plus
  `/Applications/Xcode_<major>-<minor>.app` symlink for repos
  pinning either form in `.xcode-version`.
- iOS / tvOS / watchOS / visionOS simulator runtimes from
  `xcodebuild -downloadAllPlatforms`.
- Dev tools via brew: `xcodes`, `xcbeautify`, `swiftformat`,
  `swiftlint`, `swiftgen`, `licenseplist`, `mint`, `carthage`,
  `fastlane`, `cocoapods`, `libimobiledevice`, `ideviceinstaller`,
  `ios-deploy`.
- Apple WWDR + Developer ID Certification Authority certificates
  in the system trust store.
- Everything the base ships: brew, mise, gh, git-lfs, jq, yq,
  node@24, rbenv (Ruby 2.7 + latest 3.x), awscli, the Tart guest
  agent, /Users/runner → /Users/admin symlink for GH-hosted-runner
  path compatibility.

The Tuist CLI is **not** preinstalled. Customer workflows install
it themselves via mise / brew so the version is theirs to pin.

## Quarterly maintenance: xcodes signin

The build workflow runs `xcodes download <version>` on the
bare-metal `vm-image-builder` Mac mini against `developer.apple.com`.
That call authenticates against the xcodes session cached in the
host's login keychain. Apple's session lifetime is ~30 days in
practice, sometimes longer — when it expires, `xcodes download`
fails non-interactively (Apple's 2FA challenge has nowhere to
answer) and the workflow returns the auth error.

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

Re-run the failed workflow.

The Apple ID used here is the one designated in our 1Password
vault under `Tuist macOS image-builder Apple ID`.

## Triggering a build

```
gh workflow run macos-xcode-image.yml -f xcode_version=26.4.1
```

The push tag is derived from the major-minor of `xcode_version`:
26.4.1 → `:26-4`. To bring up a new Xcode minor in parallel with
the old one (e.g. running `:26-4` and `:26-5` side-by-side for
customer-selectable profiles), trigger the workflow twice with
the two versions. Both end up in GHCR under their respective
tags.

## Promoting a new Xcode to customer runners

This image is just the base layer — pushing `:26-5` doesn't
automatically roll customer runners to Xcode 26.5. To promote:

1. Trigger this workflow with the new `xcode_version`. Verify the
   tag appears in GHCR.
2. Bump `XCODE_VERSION` in `.github/workflows/release.yml` (env
   block) so subsequent runner-image releases build against the
   new base. Merge.
3. The next `release-runner-image` run rebuilds
   `tuist-runner:macos-<major>-<minor>` against the new base and
   rewrites the chart's `runnersFleet.runnerImage` digest pin.

The xcresult-processor release flow picks up the new base on its
next server release the same way.
