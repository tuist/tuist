---
{
  "title": "Release channels",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "How Tuist ships the server and Kura Docker images across the canary, release candidate, and stable channels, and how to pin your deployment to a line you can trust."
}
---

# Release channels {#release-channels}

The Tuist server and the Kura cache mesh ship through three GHCR image channels with different stability guarantees. The recommended install is **stable** and moves once a week: it does not advance every time a feature merges to `main`, so upgrading no longer means absorbing a batch of unrelated changes. Early adopters can still run per-commit builds on **canary**, and the **release candidate** channel lets you soak an upcoming line before it becomes stable.

The server and Kura both ride the same weekly train, and both fire in lockstep with the [Tuist CLI's release schedule](/en/cli/release-channels).

## The channels {#the-channels}

| Channel | Version format | Cadence | Moves `:latest`? |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N` (e.g. `1.351.0-canary.5`) | Every commit to `main` | No, explicit opt-in |
| Release candidate | `X.Y.0-rc.N` (e.g. `1.351.0-rc.1`) | Cut from `main` every Monday, soaks ~1 week | No, explicit opt-in |
| Stable | `X.Y.Z` (e.g. `1.350.2`, `1.351.0`) | Promoted every Monday after a clean soak | **Yes** |

Canary and release-candidate builds are published as GitHub prereleases. Any tool that excludes prereleases when resolving `:latest` will skip them, so you only ever land on one of them by asking for it explicitly.

### Canary {#canary}

Every commit to `main` publishes a canary image. Canary always represents the **next unreleased minor**: once a line is cut for release, `main` advances to the following minor (for example, from `1.350.0-canary.42` to `1.351.0-canary.1`). Canary is the right channel for a staging environment that mirrors production and gives you the earliest possible signal on regressions, or to verify that a fix you reported behaves as expected before it reaches stable.

```
ghcr.io/tuist/tuist:1.351.0-canary.5
ghcr.io/tuist/kura:0.55.0-canary.5
```

### Release candidate {#release-candidate}

When a minor is ready to ship, its line is frozen onto a protected `releases/server-<major>.<minor>.x` (or `releases/kura-<major>.<minor>.x`) branch and published as `X.Y.0-rc.1`. The line is feature-frozen; only critical fixes and regressions are cherry-picked onto it, and each accepted fix iterates the release candidate (`-rc.2`, `-rc.3`, and so on). After the soak period concludes cleanly, the line is promoted to stable the following Monday.

```
ghcr.io/tuist/tuist:1.351.0-rc.1
ghcr.io/tuist/kura:0.55.0-rc.1
```

### Stable {#stable}

Stable is the recommended channel and the one all documentation points to. A stable minor (`X.Y.0`) is published only when a release candidate has soaked cleanly, and it does **not** advance when new features merge to `main`. Patches (`X.Y.1`, `X.Y.2`, and so on) on a stable line contain backported fixes only, never new features. `:latest` moves only on a stable promote.

```
ghcr.io/tuist/tuist:1.351.0
ghcr.io/tuist/kura:0.55.0
ghcr.io/tuist/tuist:latest
ghcr.io/tuist/kura:latest
```

## The Monday train {#the-monday-train}

Every Monday at 06:00 UTC, the three components' release trains fire in lockstep:

1. **06:00 UTC** — the promote jobs run. Each promotes the newest release-candidate line that is not yet stable (normally the line cut the previous Monday) and does nothing when there is none.
2. **After each promote completes** — the release-candidate job cuts the next line from `main`, so a freshly cut line is never promoted in the same run.

A failed promote holds the cut back: only the highest release-candidate line above the latest stable is ever picked, so cutting the next line on top of a failure would strand the one that did not ship. The following Monday retries the held-back line automatically.

## Pinning a channel {#pinning-a-channel}

Pin the specific tag you want in your deployment manifest, Helm values, or Docker Compose file. Example, using the Helm chart:

```yaml
server:
  image:
    repository: ghcr.io/tuist/tuist
    tag: "1.350.2"          # Pinned to a stable patch
    # tag: "1.351.0-rc.1"   # Or opt into a release candidate to soak it
    # tag: "1.351.0-canary.5" # Or opt into a specific canary build

kuraRuntime:
  image:
    repository: ghcr.io/tuist/kura
    tag: "0.54.0"           # Same three channels apply to Kura
```

`:latest` on both `ghcr.io/tuist/tuist` and `ghcr.io/tuist/kura` tracks the newest stable, moved only on the Monday promote. Pinning `:latest` gives you the weekly stable cadence without having to update the tag; pinning a specific version gives you total control over when you upgrade.

## Recommended strategy {#recommended-strategy}

The channels exist so you can decouple "getting the newest fixes" from "getting the newest features". A safe, low-effort default is:

1. **Pin production to a stable minor line**, for example `ghcr.io/tuist/tuist:1.351`. That line receives only backported fixes, never new features, so day-to-day upgrades stay low-risk. Bump the pin when you are ready to adopt the next minor.
2. **Run a staging environment on canary or on a specific release-candidate tag.** Staging catches the regressions that would otherwise reach your users, and the closer to `main` staging tracks, the earlier you find them. A staging environment on the current release-candidate line is a good middle ground: it soaks the exact bytes that will become stable next Monday.
3. **Follow the [Server changelog](/changelog) for what actually shipped.** Every stable promote is announced there with the list of pull requests that made it in.

If you would rather have new features roll out to production automatically as they become stable, keep production on `:latest`. Just be aware that the tag advances weekly on Monday morning, so schedule your deploy window accordingly.

## Backports {#backports}

Two stable server (and Kura) lines are actively maintained at any time: the current line takes regressions and security fixes as backport pull requests, and the previous line takes critical and security fixes only. Older lines are not backported; upgrade to a maintained line to receive fixes. When a new line is promoted to stable, the line that was current becomes "previous", and the line that was "previous" stops receiving backports.

Backports are cut on demand as `X.Y.(Z+1)` patch releases. They never move `:latest`.
