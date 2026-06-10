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
| 26.3            | `:26-3`            | `/Applications/Xcode_26.3.app`       | _(none — already major-minor)_ |
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
        ↓ + Xcode + dev tools + WWDR certs   <- this image, full (Layer 1)
ghcr.io/tuist/macos-tahoe-xcode:26-4-1
        ↓ + runner agent + dispatch loop     <- infra/runner-image (Layer 2a)
ghcr.io/tuist/tuist-runner:macos-26-4-1
                                              <- shipped to customer runner Macs

ghcr.io/cirruslabs/macos-tahoe-base:latest   <- same vendor base
        ↓ + Xcode only (slim=true)           <- this image, slim (Layer 1')
ghcr.io/tuist/macos-tahoe-xcode-slim:26-5
        ↓ + Erlang release + launchd unit    <- infra/xcresult-processor-image (Layer 2b)
ghcr.io/tuist/tuist-xcresult-processor:<server-semver>
                                              <- runs on internal macOS fleet
```

The runner and xcresult-processor bases diverge: runners get the
**full** image (customer CI needs the sims + tools); the
xcresult-processor gets the **slim** image (it only parses bundles).
See [Slim variant](#slim-variant) below.

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

## Slim variant

`gh workflow run macos-xcode-image.yml -f xcode_version=26.5 -f slim=true`
produces `ghcr.io/tuist/macos-tahoe-xcode-slim:<tag>` from the same
template (`slim = true`). It keeps `Xcode.app` fully intact — the
xcresult-processor's NIF shells out to `xcrun xcresulttool`, which
only ships in full Xcode, and stripping bits out of the bundle would
break the framework closure it loads at parse time — but skips:

- the simulator runtimes (`xcodebuild -downloadAllPlatforms`),
- the brew CI dev-tool grab-bag,
- the Apple WWDR / Developer ID signing certs.

Only the **xcresult-processor** consumes it. That service merely
*parses* `.xcresult` bundles (it never runs tests), so it has no use
for sims, CI tools, or signing certs. Runners MUST stay on the full
image — customer CI needs all of that.

Why bother: the processor runs as a k8s Deployment on Scaleway Mac
minis with a fixed **1 GbE** NIC (~125 MB/s). A rolled Pod boots a
fresh Tart VM = a cold image pull, and the Deployment's progress
deadline trips if that pull is too slow, which fails the server
deploy under `helm --atomic` and thrashes. Measured compressed pull
sizes (sum of OCI layer sizes ÷ 125 MB/s):

| Image | Pull | Time |
|---|---|---|
| `cirruslabs/macos-tahoe-base` (macOS floor) | 27 GB | 3.6 min |
| `macos-tahoe-xcode` (full: +sims +tools +certs) | 60 GB | 8.0 min |
| `tuist-xcresult-processor` on the full base | 60 GB | 8.0 min |

Dropping the sims (the single biggest removable chunk) + tools +
certs is what gets the processor's pull comfortably under the
deadline. The processor Deployment also widens its
`progressDeadlineSeconds` (chart value `xcresultProcessor.progressDeadlineSeconds`)
as belt-and-braces for VM-create + boot + 1 GbE variance.

The slim base is needed only for the one Xcode version the processor
pins (`release.yml`'s `XCODE_VERSION`, kept ≥ the newest active
runner profile). Build it with `slim=true` *before* the processor
image builds against it — see the promotion runbook below.

## Apple-auth-free CI: the `xcode-xips` mirror

The build workflow does **not** talk to Apple. It pulls the .xip
from `ghcr.io/tuist/xcode-xips:<version>` via oras — an in-house
mirror that holds every Xcode .xip we've published. CAPI-managed
builder Macs can rotate without breaking CI; the workflow has no
session state to lose.

The mirror is operator-populated. Apple's `developer.apple.com`
auth requires a real Apple ID + post-2FA cookies that we can't
keep alive non-interactively in the cluster (xcodes can't be
driven without 2FA when its session lapses, Apple migrated the
signin endpoint to SRP so plain `curl` is out, and there's no
machine-credential surface that authorises Xcode downloads). So
we run that part locally on demand and skip the in-cluster
auto-download entirely:

1. **Notification: subscribe Slack to `xcodereleases.com`'s RSS
   feed.** In whichever Slack channel handles infra ops:

   ```
   /feed subscribe https://xcodereleases.com/api/all.rss
   ```

   You'll get a message in the channel within minutes of any new
   Xcode (or RC, beta, etc.) Apple ships. xcodereleases.com is
   the same data source xcodes uses internally and has been
   community-maintained since 2019.

2. **Upload the .xip to the mirror — `mise run xcode-mirror:upload
   <version>`.** On any maintainer's Mac:

   ```
   mise run xcode-mirror:upload 26.5.0
   ```

   The task uses `xcodes` to authenticate against Apple (the
   maintainer's keychain caches the post-2FA session, so this is
   prompt-free after the first run per ~30-day window), downloads
   the .xip, and `oras push`es it to
   `ghcr.io/tuist/xcode-xips:<version>`. ~10 min wall-clock for
   the download; ~2 min for the push.

3. **Promote**. For runner-image: edit the active-profile matrix in
   `.github/workflows/release.yml` (`runner-image-build.strategy.matrix.xcode`)
   — add the new Xcode as an additional entry (additional profile)
   or put it first (makes it the chart's default profile) — then
   merge. The release flow rebuilds every matrix entry against its
   matching base and moves the chart's `runnersFleet.runnerImage`
   digest pin to the first-entry profile. For the xcresult-processor,
   first publish the **slim** base for that Xcode
   (`gh workflow run macos-xcode-image.yml -f xcode_version=26.X.Y -f slim=true`),
   then bump the inline `XCODE_VERSION` env var on `release.yml`'s
   `release-xcresult-processor-image.Build image` step in the same
   commit — it should track at least as new an Xcode as the newest
   active runner-image profile (xcresulttool's JSON schema changes
   across Xcode majors). The processor builds on
   `macos-tahoe-xcode-slim`, not the full runner base.

The Apple ID used for the local mint is the one stored in 1Password
under `Tuist Apple ID` (Employee vault). `mise.toml` pins the
operator's `xcodes` + `oras` versions so anyone running the task
gets the same toolchain.

## Triggering a build

```
gh workflow run macos-xcode-image.yml -f xcode_version=26.4.1
gh workflow run macos-xcode-image.yml -f xcode_version=26.3
gh workflow run macos-xcode-image.yml -f xcode_version=26.5
# slim variant for the xcresult-processor base:
gh workflow run macos-xcode-image.yml -f xcode_version=26.5 -f slim=true
```

Push tag: 26.4.1 → `:26-4-1`, 26.3 → `:26-3`, 26.5 → `:26-5`. Each invocation
publishes a fresh image — multiple Xcode versions exist in GHCR
side-by-side under their respective tags, and the customer
fleet's profile picker chooses between them. The `slim=true`
dispatch publishes `macos-tahoe-xcode-slim:<tag>` instead; full and
slim builds of the same version can run concurrently (distinct tags,
distinct concurrency groups).

The current Tahoe-era profile set is:
- `:26-5` (latest 26.5.x, no patch released yet)
- `:26-4-1`
- `:26-3`
- `:26-2-y`
- `:26-1-y`
- `:26-0-y`

To bring up the full set on a fresh GHCR, dispatch this workflow
six times — once per Xcode version we want available as a
profile. Subsequent patch bumps from Apple (e.g. 26.4.1 → 26.4.2)
republish under a *new* tag (`:26-4-2`); the operator promotes by
editing the active-profile matrix in `.github/workflows/release.yml`.

## Promoting a new Xcode to customer runners

This image is just the base layer — pushing `:26-5` doesn't
automatically roll customer runners to Xcode 26.5. To promote:

1. Trigger this workflow with the new `xcode_version`. Verify the
   tag appears in GHCR.
2. Edit `.github/workflows/release.yml`'s
   `runner-image-build.strategy.matrix.xcode` list: append the new
   Xcode (most common — gives customers it alongside the existing
   default), or put it first to make it the chart's default profile.
   When moving the first entry, update the adjacent "Resolve default
   profile + digest" step to match. Commit with a `feat(runner-image): ...`
   message so check-releases picks it up. To retire an Xcode, drop
   its matrix entry — the `:macos-<dashes>` tag stays in GHCR for
   lingering pins; use `runner-image.yml` dispatch for one-off
   refreshes.
3. Publish the **slim** base for the processor's Xcode
   (`gh workflow run macos-xcode-image.yml -f xcode_version=26.X.Y -f slim=true`),
   then bump the inline `XCODE_VERSION` on `release.yml`'s
   `release-xcresult-processor-image.Build image` step in the same
   commit so the processor doesn't lag a newly-active runner profile.
   The processor builds on `macos-tahoe-xcode-slim`, so its base must
   exist before `release-xcresult-processor-image` runs.
4. After merge, `release-runner-image` rebuilds
   `tuist-runner:macos-<xcode-version-dashes>` against the new
   base and rewrites the chart's `runnersFleet.runnerImage`
   digest pin; `release-xcresult-processor-image` does the same
   on the next server release.
