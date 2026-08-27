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
| 27.0-beta-6     | `:27-0-beta-6`     | `/Applications/Xcode_27.0-beta-6.app`| `Xcode_27.0.app` → `Xcode_27.0-beta-6.app` |

When `xcode_version` carries a patch component (three-segment
`X.Y.Z`), the image lays down a symlink at the matching
`/Applications/Xcode_<major>.<minor>.app` path so repos pinning
the major-minor form in `.xcode-version` resolve to the patched
Xcode. Two-segment inputs (`X.Y`) don't get an extra alias —
the bundle is already at the major-minor path.

Prereleases take the same path. `xcode_version` is never Apple's
own string, which carries spaces ("27.0 Beta 6") that no push tag,
bundle path, RunnerPool name or k8s label can hold; it is the slug
`mise run xcode-mirror:upload` derives from it (lowercase, spaces
to dashes). Stable releases are already their own slug, so nothing
changes for them. The major-minor alias applies to betas too, and
`Xcode_27.0.app` is not a lie about one: 27.0 is the marketing
version Apple gives the beta and what `xcodebuild -version`
reports from inside it.

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
(unxip, license accept, runFirstLaunch, downloadAllPlatforms, and
download Metal Toolchain). If that lived in the runner-image /
xcresult-processor packer files,
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
- The Metal compiler toolchain from
  `xcodebuild -downloadComponent MetalToolchain`.
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
mirror that holds every Xcode .xip we've published. CAPI-managed
builder Macs can rotate without breaking CI; the workflow has no
session state to lose.

**Why this one stays on GHCR.** Every image this workflow *publishes*
goes to the Tuist OCI registry on the tailnet, but the .xip mirror it
*reads* deliberately does not follow, and it is the only artifact in
the set that is not anonymously pullable (hence the explicit `oras
login ghcr.io` in the workflow). The reason is the writer, not the
reader: the mirror's only writer is `mise run xcode-mirror:upload`
running on a maintainer's Mac over a home link. Measured from one with
the same 512 MB blob, that push is 136s to GHCR against 481s to the
tailnet-only registry: a ten-minute upload one way, closer to forty
the other. Worse, a fresh Tailscale session starts on a DERP relay and
only upgrades to a direct path once NAT traversal succeeds; over the
relay these uploads fail outright rather than merely crawl, which is
exactly what an occasional, once-per-Xcode-release task gets. GHCR's
rate limits were never the problem for a single-blob artifact pushed a
handful of times a year. They were the problem for the ~50 GB images,
and those are pushed from a builder over a datacenter link and do go
to our registry. Revisit only if the upload path stops being a
maintainer laptop.

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
   mise run xcode-mirror:upload "27.0 Beta 6"
   ```

   The argument is the version string exactly as `xcodes list`
   prints it, because `xcodes download` has to resolve it against
   Apple's catalog and accepts no other form. The task slugs it
   (lowercase, spaces to dashes) and prints the result — that slug
   is the mirror tag and the `xcode_version` every later step
   takes.

   The task uses `xcodes` to authenticate against Apple (the
   maintainer's keychain caches the post-2FA session, so this is
   prompt-free after the first run per ~30-day window), downloads
   the .xip, and `oras push`es it to
   `ghcr.io/tuist/xcode-xips:<slug>`. ~10 min wall-clock for
   the download; ~2 min for the push.

3. **Promote**. For a stable Xcode, add it to
   `infra/runner-image/profiles.json` and to
   `runnersFleet.xcodeVersions` in
   `infra/helm/tuist/values-managed-common.yaml`, with an
   `xcodeOverrides` entry per env — see "Promoting a new Xcode to
   customer runners" below. Betas take a different route, because
   they must reach the fleet on Apple's cadence rather than the
   server's; see "Promoting an Xcode beta". For the
   xcresult-processor, bump the inline `XCODE_VERSION` env var on
   `server-production-deployment.yml`'s
   `release-xcresult-processor-image.Build image` step — it should
   track at least as new a *stable* Xcode as the newest active
   runner-image profile (xcresulttool's JSON schema changes across
   Xcode majors). Never point it at a beta: it parses customer
   xcresults for the whole fleet, so a schema change Apple is still
   moving would land on every account at once.

The Apple ID used for the local mint is the one stored in 1Password
under `Tuist Apple ID` (Employee vault). `mise.toml` pins the
operator's `xcodes` + `oras` versions so anyone running the task
gets the same toolchain.

## Triggering a build

```
gh workflow run macos-xcode-image.yml -f xcode_version=26.4.1
gh workflow run macos-xcode-image.yml -f xcode_version=26.3
gh workflow run macos-xcode-image.yml -f xcode_version=26.0.1
gh workflow run macos-xcode-image.yml -f xcode_version=26.5
gh workflow run macos-xcode-image.yml -f xcode_version=27.0-beta-6
```

Push tag: 26.4.1 → `:26-4-1`, 26.3 → `:26-3`, 26.0.1 → `:26-0-1`,
26.5 → `:26-5`, 27.0-beta-6 → `:27-0-beta-6`. Each invocation
publishes a fresh image — multiple Xcode versions exist in GHCR
side-by-side under their respective tags, and the customer
fleet's profile picker chooses between them.

The current Tahoe-era profile set is:
- `:26-6`
- `:26-5`
- `:26-4-1`
- `:26-3`
- `:26-0-1`
- `:27-0-beta-<n>` for the current Xcode 27 beta

Every tag is immutable, betas included: a new beta or patch bump
from Apple (26.4.1 → 26.4.2, beta 6 → beta 7) republishes under a
*new* tag, never over an existing one. The operator promotes by
editing `infra/runner-image/profiles.json` (stable) or the beta
pool's `imageTag` (prereleases), per the two sections below.

## Promoting a new Xcode to customer runners

This image is just the base layer — pushing `:26-5` doesn't
automatically roll customer runners to Xcode 26.5. To promote:

1. Trigger this workflow with the new `xcode_version`. Verify the
   tag appears in GHCR.
2. Add the version to `infra/runner-image/profiles.json`. That list
   is the build matrix `server-production-deployment.yml` expands,
   and it sits under the runner-image component's `include_paths`,
   so editing it both reshapes the matrix and triggers a
   runner-image release. Commit with a `feat(runner-image): ...`
   message so check-releases picks it up. To retire an Xcode, drop
   its entry — the `:macos-<dashes>` tag stays in GHCR for
   lingering pins; use `runner-image.yml` dispatch for one-off
   refreshes.
3. Add a matching `runnersFleet.xcodeVersions` entry in
   `infra/helm/tuist/values-managed-common.yaml` and an
   `xcodeOverrides` entry in each of the three managed env values
   files. The catalog entry is what renders the RunnerPool and what
   the Runner Profiles dropdown offers; `default: true` marks the
   version `runs-on: tuist-macos` resolves to. A catalog entry with
   no runner image built for it renders a pool that can never pull.
4. Bump the inline `XCODE_VERSION` on
   `server-production-deployment.yml`'s
   `release-xcresult-processor-image.Build image` step in the same
   commit so the processor doesn't lag a newly-active runner profile.
5. After merge, `release-runner-image` rebuilds
   `tuist-runner:macos-<xcode-version-dashes>-<semver>` against the
   new base and the chart's pools pick it up on deploy;
   `release-xcresult-processor-image` does the same on the next
   server release.

## Promoting an Xcode beta

Betas do not go through `profiles.json`. Apple ships one every
few weeks and stops accepting TestFlight uploads built with
superseded ones, so the fleet has to move on Apple's cadence
rather than wait for whenever `infra/runner-image/**` next changes
and triggers a runner-image release. They also must not churn the
catalog: a customer's Runner Profile stores the `xcode_version`
string, and removing the one it names strands the profile on a
RunnerPool that no longer renders — its jobs then queue forever
rather than failing.

Both fall out of one split. The catalog entry is the channel
(`27.0-beta`) and never changes across betas; the image behind it
is pinned exactly, per beta, by `imageTag`:

```yaml
# values-managed-common.yaml
runnersFleet:
  xcodeVersions:
    - xcodeVersion: "27.0-beta"
```

```yaml
# values-managed-{staging,canary,production}.yaml
runnersFleet:
  xcodeOverrides:
    "27.0-beta":
      # Xcode 27.0 beta 6 (27A5252f)
      imageTag: "macos-27-0-beta-6-<sha8>"
      autoscaling:
        enabled: true
        minWarmPoolFloor: 0
        maxReplicas: 13   # 1 in staging/canary
```

Keep `minWarmPoolFloor` at 0. The floors are drawn against the
fleet's guest-slot budget, and a beta pool holding a warm slot
parks a whole mini for traffic that is by definition
experimental.

To move the channel onto a new beta:

1. `mise run xcode-mirror:upload "27.0 Beta 7"` on a maintainer
   Mac. Note the slug it prints (`27.0-beta-7`).
2. `gh workflow run macos-xcode-image.yml -f xcode_version=27.0-beta-7`.
   Publishes `macos-tahoe-xcode:27-0-beta-7`. Budget a couple of
   hours for a fresh major — `-downloadAllPlatforms` pulls
   simulator runtimes Apple hasn't cached anywhere yet, and the
   ~50 GB image upload follows.
3. `gh workflow run runner-image.yml -f xcode_version=27.0-beta-7`.
   Publishes `tuist-runner:macos-27-0-beta-7-<sha8>`; the run's
   push step logs the full tag.
4. Repoint `imageTag` at that tag in the three env values files,
   with the beta and build number in the comment above it, and
   merge. The deploy rolls the pool; no customer profile changes.

Steps 1-3 publish only new tags, so they are safe to run ahead of
the merge and are what makes step 4 a one-line edit that can be
reverted to the previous beta if the new one misbehaves.

When the major goes stable, promote `27.0` through the normal
stable path above and leave `27.0-beta` in the catalog until
accounts have moved their profiles off it — dropping the entry is
what strands them, and the entry costs nothing while its pool sits
at `minWarmPoolFloor: 0`.
