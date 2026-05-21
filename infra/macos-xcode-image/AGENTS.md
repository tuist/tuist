# macOS + Xcode Image

In-house replacement for `ghcr.io/cirruslabs/macos-tahoe-xcode:N`.
A Tart VM image that bundles macOS Tahoe + a **single** Xcode +
the dev tools customer iOS/macOS workflows expect.

Built by `.github/workflows/macos-xcode-image.yml` on
workflow_dispatch (we trigger it whenever Apple ships a new Xcode
and we want it in the fleet, regardless of whether Cirrus has
caught up).

Per-Xcode image model — one Xcode per image, profile-selectable
downstream. This mirrors Namespace's UX: each customer-facing
profile (`runs-on: tuist-macos-xcode-26-4`, "Tahoe with Xcode
26.4.x", etc.) maps onto a single image variant produced here.
GitHub-hosted bakes ~6 Xcodes into one giant image so customers
can `xcode-select` between them at job time; we explicitly didn't
want that, because the choice happens at job-routing time, not
xcode-select time, and a per-Xcode image is smaller, faster to
pull, and faster to build.

Published to `ghcr.io/tuist/macos-tahoe-xcode:<xcode-version-dashes>`:

| `xcode_version` | Pushed tag         | Bundle path                          | Alias                          |
|-----------------|--------------------|--------------------------------------|--------------------------------|
| 26.5            | `:26-5`            | `/Applications/Xcode_26.5.app`       | _(none — already major-minor)_ |
| 26.4.1          | `:26-4-1`          | `/Applications/Xcode_26.4.1.app`     | `Xcode_26.4.app` → `Xcode_26.4.1.app` |
| 26.0.1          | `:26-0-1`          | `/Applications/Xcode_26.0.1.app`     | `Xcode_26.0.app` → `Xcode_26.0.1.app` |

When `xcode_version` carries a patch component (three-segment
`X.Y.Z`), the image lays down a symlink at the matching
`/Applications/Xcode_<major>.<minor>.app` path so repos pinning
the major-minor form in `.xcode-version` resolve to the patched
Xcode. Two-segment inputs (`X.Y`) don't get an extra alias —
the bundle is already at the major-minor path.

## Architecture: Layer 1 base for Tuist's macOS images

```
ghcr.io/cirruslabs/macos-tahoe-base:latest   <- vendor base
        ↓ + Xcode + dev tools + WWDR certs   <- this image (Layer 1)
ghcr.io/tuist/macos-tahoe-xcode:26-4-1
        ↓ + runner agent + dispatch loop     <- infra/runner-image (Layer 2a)
ghcr.io/tuist/tuist-runner:macos-26-4-1
                                              <- shipped to customer runner Macs

ghcr.io/tuist/macos-tahoe-xcode:26-4-1       <- same Layer 1
        ↓ + Erlang release + launchd unit    <- infra/xcresult-processor-image (Layer 2b)
ghcr.io/tuist/tuist-xcresult-processor:<server-semver>
                                              <- runs on internal macOS fleet
```

Why split this layer out: the Xcode install is ~30 min of work
(unxip, license accept, runFirstLaunch, downloadAllPlatforms). If
that lived in the runner-image / xcresult-processor packer files,
every `fix(runner-image): ...` commit on main would pay the cost
again. With the split, Layer 2 builds re-clone Layer 1 and lay a
thin runtime on top — ~2 min instead of ~30.

## What's in the image

- One Xcode at `/Applications/Xcode_<xcode_version>.app`. When
  `xcode_version` is three-segment (has a patch), an additional
  `/Applications/Xcode_<major>.<minor>.app` symlink resolves to
  the same bundle.
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
  agent, `/Users/runner` → `/Users/admin` symlink for
  GH-hosted-runner path compatibility.

The Tuist CLI is **not** preinstalled. Customer workflows install
it themselves via mise / brew so the version is theirs to pin.

## Apple-auth-free CI: the `xcode-xips` mirror

The build workflow does **not** talk to Apple. It pulls the .xip
from `ghcr.io/tuist/xcode-xips:<version>` via oras — an in-house
mirror that holds every Xcode .xip we've published. The Apple-auth
concern is confined to one of two places, neither of them tied to
a specific Mac mini:

1. **Steady state — `Tuist.XcodeMirror` in-cluster worker.** An
   Oban worker in the Tuist server polls `xcodereleases.com` every
   6 hours, diffs against `ghcr.io/tuist/xcode-xips`, downloads any
   missing versions from Apple's CDN using a session cookie jar
   stored in 1Password, and pushes them to GHCR. Operator does
   nothing per Xcode release.
2. **Break-glass — `mise run xcode-mirror:upload <version>`.**
   When the worker hasn't picked up a brand-new Xcode yet (cookies
   expired, Apple API change, version absent from
   xcodereleases.com), the local maintainer task downloads from
   Apple via xcodes and pushes to GHCR by hand. Same effect as a
   worker tick, just operator-initiated. See
   `mise/tasks/xcode-mirror/upload.sh` for prerequisites.

When the worker's session expires (~30 days in practice based on
Apple's lifetime), Sentry fires `xcode_mirror.session_expired`.
Refresh the cookie jar from any maintainer's Mac — no SSH into
any host:

```
mise run xcode-mirror:mint-session
```

The task spawns `xcodes signin`, captures the post-2FA session
cookies from xcodes' keychain entry, and writes them straight into
the 1Password item via `op item edit`. External Secrets propagates
the new value to the cluster within ~5 min; the next worker tick
uses the fresh cookies. See `server/lib/tuist/xcode_mirror/` for
the worker code and `infra/helm/tuist/templates/xcode-mirror-external-secrets.yaml`
for the secret wiring.

The Apple ID used here is the one designated in our 1Password
vault under `Tuist macOS image-builder Apple ID`.

## Triggering a build

```
gh workflow run macos-xcode-image.yml -f xcode_version=26.4.1
gh workflow run macos-xcode-image.yml -f xcode_version=26.5
```

Push tag: 26.4.1 → `:26-4-1`, 26.5 → `:26-5`. Each invocation
publishes a fresh image — multiple Xcode versions exist in GHCR
side-by-side under their respective tags, and the customer
fleet's profile picker chooses between them.

The current Tahoe-era profile set is:
- `:26-5` (latest 26.5.x, no patch released yet)
- `:26-4-1`
- `:26-3-y` (latest 26.3 patch — bump the workflow input as Apple ships patches)
- `:26-2-y`
- `:26-1-y`
- `:26-0-y`

To bring up the full set on a fresh GHCR, dispatch this workflow
six times — once per Xcode version we want available as a
profile. Subsequent patch bumps from Apple (e.g. 26.4.1 → 26.4.2)
republish under a *new* tag (`:26-4-2`); the operator promotes by
bumping the relevant Layer 2 `XCODE_VERSION` pin file.

## Promoting a new Xcode to customer runners

This image is just the base layer — pushing `:26-5` doesn't
automatically roll customer runners to Xcode 26.5. To promote:

1. Trigger this workflow with the new `xcode_version`. Verify the
   tag appears in GHCR.
2. Bump `infra/runner-image/XCODE_VERSION` and
   `infra/xcresult-processor-image/XCODE_VERSION` to the same
   value. Commit with a `feat(runner-image): bump to Xcode X.Y.Z`
   (and a parallel `feat(xcresult-processor-image): ...`) message
   so check-releases picks it up — each file lives under its
   image's release-include-path, so a touch is what triggers the
   Layer 2 rebuild.
3. After merge, `release-runner-image` rebuilds
   `tuist-runner:macos-<xcode-version-dashes>` against the new
   base and rewrites the chart's `runnersFleet.runnerImage`
   digest pin; `release-xcresult-processor-image` does the same
   on the next server release.
