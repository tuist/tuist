---
{
  "title": "Compatibility",
  "titleTemplate": ":title · References · Tuist",
  "description": "How long the Tuist server supports older CLI releases, what the support window means for upgrades, and what happens to versions outside it."
}
---

# Compatibility {#compatibility}

The Tuist CLI talks to the Tuist server for features such as the cache, build and test insights, previews, and the registry. Your team and CI rarely upgrade the CLI on the same cadence the server ships on, so the server keeps working with older CLI releases for a defined window.

## Support window {#support-window}

The Tuist server supports CLI releases from the **last 3 months**. Within that window the server stays backward compatible: any CLI released in the last 3 months keeps building, caching, and running tests against the server, and you can upgrade the CLI on your own schedule without a server change breaking you.

The CLI follows [semantic versioning](https://semver.org). Any release published within the last 3 months is supported.

This applies to the managed server at `https://tuist.dev`. If you self-host Tuist, you control when the server and CLI upgrade, so you set your own compatibility window.

## Outside the window {#outside-the-window}

CLI releases older than the support window are considered deprecated. The server still responds, but:

- Newer server-side features may not work with that version.
- Server-backed commands may print a warning asking you to upgrade.

Behavior on deprecated versions is not guaranteed. If you are on one, upgrade to a release within the support window.

## How we keep the promise {#how-we-keep-the-promise}

Backward compatibility is verified, not assumed. Every server deployment runs an automated acceptance test against the **oldest CLI version still inside the support window**, exercising the cache pull path end to end. If a change would break that version, the deployment is blocked before it reaches production. This runs alongside the tests against the latest CLI, so a regression for older clients is caught the same way a regression for the newest one is.

## Recommendation {#recommendation}

Upgrade the CLI at least once every 3 months to stay within the supported window. Pinning the CLI version in CI and bumping it on a regular cadence keeps your team on a consistent, supported release.
