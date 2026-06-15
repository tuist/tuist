---
title: "Release channels: a stable line teams can trust"
category: "engineering"
tags: ["engineering", "releases", "cli", "open-source"]
excerpt: "Until now, every commit to main became the latest Tuist release. We are changing that. The CLI now ships through three channels, canary, release candidate, and stable, so the version we recommend moves slowly and predictably, and upgrading stops meaning you absorb a batch of unrelated changes."
author: fortmarek
---

Releasing the CLI used to be a manual step. Then we adopted conventional commits and [git-cliff](https://git-cliff.org) and moved to continuous release: every commit that landed on `main` became the new latest version. It served us well. It kept the feedback loop short and meant fixes reached you within minutes of merging.

But continuous release has a cost that grows with the size of your team. When every commit is "latest", upgrading is a gamble. A version that has the fix you need also carries every unrelated change merged around it, and occasionally one of those is a regression. The advice we kept repeating, "pin a version and upgrade carefully", was a workaround for a problem we had created. We wanted to fix it at the source.

So we are introducing release channels.

## Three channels

The CLI now ships through three channels with different stability guarantees.

| Channel | Version | Cadence | Resolved by default? |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N` | Every commit to `main` | No, opt-in |
| Release candidate | `X.Y.0-rc.N` | Cut from `main`, soaks for about a week | No, opt-in |
| Stable | `X.Y.Z` | Promoted after a clean soak | Yes |

**Canary** is the bleeding edge. Every commit to `main` still publishes a build, exactly as before, but now as a prerelease that package managers do not pick up unless you ask for it. It is the right channel for early adopters who want the earliest possible signal.

**Release candidates** are cut from `main` when a minor is ready to ship. The line is feature-frozen and soaks for about a week. Only critical fixes and regressions are pulled in during that window, each bumping the RC.

**Stable** is the channel we recommend, and the one all of our documentation points to. A stable release is published only when a release candidate has soaked cleanly, and it does not move when new features merge into `main`. Patches on a stable line carry backported fixes only, never new features.

## What this means for you

The practical change is that the recommended install is now slow-moving and predictable. With [Mise](https://tuist.dev/en/docs/guides/install-tuist):

```bash
mise use tuist@latest   # Latest stable, the recommendation
mise use tuist@4.200    # Pin to a stable line; backported fixes only, never features
```

Pin to a stable line and you keep receiving fixes without ever being surprised by a new feature. When you are ready to adopt the next minor, you do it deliberately, and you can soak it on the release candidate channel first. `tuist@latest` and `brew install tuist` continue to give you the latest stable; canary and RC builds are prereleases, so they are only ever installed on purpose.

We keep two stable lines maintained at a time. The current line receives regressions and security fixes; the previous line receives critical and security fixes only. Independently of the channel you choose, the Tuist server stays compatible with any CLI released in the last three months, so pinning to a stable line never pushes you outside the supported window as long as you upgrade within that period.

You can read the full details, including how to opt into a prerelease, on the [Release channels](https://tuist.dev/en/docs/cli/release-channels) page.

## Where we are, and a request

The current stable release is [4.200.5](https://github.com/tuist/tuist/releases/tag/4.200.5). Next week we plan to cut the first release candidate of the next minor. About a week after that, once it has soaked, we will promote it to stable. From there, this becomes our regular rhythm.

The soak only works if the release candidate is actually exercised before it becomes stable. So we are looking for teams who would be up for running the RC in their CI or locally while it soaks, and telling us if anything breaks. It is the most direct way to make sure a release is genuinely stable on the day we recommend it, and it gives your team an early, low-risk look at what is coming.

If that sounds like you, let us know on the [community forum](https://community.tuist.dev) or through your usual Tuist contact. This change came out of an [RFC](https://community.tuist.dev/t/rfc-release-channels-and-a-stable-line-teams-can-trust/994), and we would love to keep shaping the cadence together with the teams who depend on it.
