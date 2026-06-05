---
{
  "title": "Compatibility",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "How long the Tuist server supports older CLI releases, what the support window means for upgrades, and what happens to versions outside it."
}
---

# Compatibility {#compatibility}

The Tuist CLI talks to the Tuist server for features such as the cache, build and test insights, previews, and the registry. The server ships continuously and independently of when you upgrade the CLI, so a server change must not break the CLI version you are running. To guarantee that, the server stays compatible with recent CLI releases for a defined window.

## Support window {#support-window}

The Tuist server supports CLI releases from the **last 3 months**. Within that window the server stays backward compatible: any CLI released in the last 3 months keeps building, caching, and running tests against the server, and you can upgrade the CLI on your own schedule without a server change breaking you.

The CLI follows [semantic versioning](https://semver.org). Any release published within the last 3 months is supported.

## Outside the window {#outside-the-window}

CLI releases older than the support window are considered deprecated. The server still responds, but:

- Newer server-side features may not work with that version.
- Server-backed commands may print a warning asking you to upgrade.

Behavior on deprecated versions is not guaranteed. If you are on one, upgrade to a release within the support window.

## How we keep the promise {#how-we-keep-the-promise}

Backward compatibility is verified, not assumed. Every server deployment runs an automated acceptance test against the **oldest CLI version still inside the support window**, which today is **4.155.0**, exercising the cache pull path end to end. If a change would break that version, the deployment is blocked before it reaches production. This runs alongside the tests against the latest CLI, so a regression for older clients is caught the same way a regression for the newest one is.

## Recommendation {#recommendation}

Upgrade the CLI at least once every 3 months to stay within the supported window. Pinning the CLI version in CI and bumping it on a regular cadence keeps your team on a consistent, supported release.
