---
{
  "title": "Release channels",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "How Tuist ships the CLI across the canary, release candidate, and stable channels, and how to pin your team to a line you can trust."
}
---

# Release channels {#release-channels}

The Tuist CLI ships through three channels with different stability guarantees. The recommended install is **stable** and moves slowly: it does not advance every time a feature merges, so upgrading no longer means absorbing a batch of unrelated changes. Early adopters can still run per-commit builds on **canary**, and the **release candidate** channel lets teams soak an upcoming line before it becomes stable.

## The channels {#the-channels}

| Channel | Version format | Cadence | Resolved by default? |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N` (e.g. `4.201.0-canary.42`) | Every commit to `main` | No — explicit opt-in |
| Release candidate | `X.Y.0-rc.N` (e.g. `4.200.0-rc.1`) | Cut from `main`, soaks ~1 week | No — explicit opt-in |
| Stable | `X.Y.Z` (e.g. `4.200.0`, `4.200.1`) | Promoted after a clean soak | **Yes** |

Canary and release candidate builds are published as prereleases. Tools like Mise and Homebrew exclude prereleases when resolving `latest`, a bare install, or a line pin, so you only ever land on one of them by asking for it explicitly.

### Canary {#canary}

Every commit to `main` publishes a canary. Canary always represents the **next unreleased minor**: once a line is cut for release, `main` advances to the following minor (for example, from `4.200.0-canary.42` to `4.201.0-canary.1`). Canary is the right channel for internal dogfooding and for verifying that a fix you contributed behaves as expected before it reaches stable.

### Release candidate {#release-candidate}

When a minor is ready to ship, its line is frozen onto a protected `releases/<major>.<minor>.x` branch and published as `X.Y.0-rc.1`. The line is feature-frozen; only critical fixes and regressions are cherry-picked, and each accepted fix increments the RC (`-rc.2`, `-rc.3`, …). After the soak period concludes cleanly, the line is promoted to stable.

### Stable {#stable}

Stable is the recommended channel and the one all documentation points to. A stable minor (`X.Y.0`) is published only when a release candidate has soaked cleanly, and it does **not** advance when new features merge to `main`. Patches (`X.Y.1`, `X.Y.2`, …) on a stable line contain backported fixes only, never new features.

## Choosing a version {#choosing-a-version}

With [Mise](/en/guides/install-tuist) (recommended):

```bash
mise use tuist@latest              # Latest stable (recommended)
mise use tuist@4.200               # Pin to a stable line; receives backported fixes only
mise use tuist@4.200.1             # Pin to an exact stable patch
mise use tuist@4.201.0-rc.1        # Opt into a release candidate to soak it
mise use tuist@4.201.0-canary.42   # Opt into a specific canary build
```

With Homebrew, `brew install --formula tuist` always installs the latest stable; prereleases are not distributed through the formula.

## Recommended strategy {#recommended-strategy}

1. **Pin to a stable line**, for example `tuist@4.200`. That line receives only backported fixes, never new features, so day-to-day upgrades stay low-risk.
2. **Adopt new features deliberately.** When you are ready for the next minor, soak it on the release candidate channel, then move your pin to the new stable line.
3. **Dogfood on canary** in a non-critical environment if you want the earliest possible signal.

## Support and backports {#support-and-backports}

Two stable lines are actively maintained at any time:

| Line | Receives |
| --- | --- |
| Current (`X.Y.x`) | All fixes: bugs, regressions, and security |
| Previous (`X.(Y-1).x`) | Critical and security fixes only |
| Older | None — upgrade to a maintained line |

Fixes land first on `main` (canary), then are cherry-picked onto the current stable line, and onto the previous line only when they are critical or security-related. When a new line is promoted to stable, the line that was current becomes "previous", and the line that was "previous" stops receiving backports.

Independently of the channel, the Tuist server stays [compatible](/en/cli/compatibility) with any CLI released in the last 3 months, so pinning to a stable line never puts you outside the supported window as long as you upgrade within that period.
