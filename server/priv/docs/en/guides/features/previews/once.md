---
{
  "title": "Once artifact publication",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Publish immutable Once application artifacts to an existing Tuist project with explicit destination authorization."
}
---
# Once artifact publication

[Once](https://buildonce.dev/docs/guide/infrastructure/tuist#publish-application-previews) can publish immutable artifacts using existing Tuist authentication. This requires Once 0.74.0+ and a Tuist server with the artifact receiver. Once 0.73.x uses the legacy single-payload adapter instead.

## Configure the destination

In the workspace's `once.toml`:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.artifacts]
name = "tuist"
```

```bash
once auth login --provider tuist
once artifact publish MyApplication --track review
```

The receiver retains the complete set, member manifests, and payloads, including unknown interfaces. Supported native interfaces are projected asynchronously into previews using the project's default visibility, access, and distribution. Generic artifact contents stay private, even in public projects. A receipt confirms artifact storage, not completion of preview processing; its URL opens the project's previews list.

## Eligible applications

Apple projection accepts `dev.once.apple-install.v2` metadata for ad-hoc signed macOS and simulator applications exported on macOS. Physical-device applications are not eligible. Android projection accepts `dev.once.android-install.v1` metadata with a verified signature. Once approves automatic publication only for debug-signed, non-instrumentation APKs. Unknown interfaces remain downloadable as artifacts without creating previews. Android installation links preserve an `.apk` filename even though payloads are stored under content digests.

## Opt in to publication after builds

```toml
[infrastructure]
publish_on_build = ["MyApplication"]
```

```bash
once artifact publish MyApplication --allow-on-build
once build MyApplication
```

All requested builds must succeed. Automatic publication also requires producer approval of the entire closure and local authorization for this machine, workspace, exact endpoint, target, and stable Tuist project destination. Without policy or authorization there are no artifact-publication network requests. Ordinary Once builds remain free of implicit publication side effects.

Replaying the same retained publication verifies the remote receipt and avoids another upload. This differs from the duplicate-build behavior of `tuist share`.

## Retention

Artifact publications expire after 30 days on hosted Tuist. Self-hosted instances use `TUIST_APP_PREVIEW_RETENTION_DAYS`; leaving it unset disables expiry for this family. Expired records remain as tombstones and cannot be reactivated by replaying the same intent. Existing `tuist share` signing, visibility, and distribution workflows remain unchanged.

See <.localized_link href="/guides/features/previews#run-a-preview">Run a preview</.localized_link> for running published builds, access, tracks, and README badges.

## Apple previews

For eligible Apple simulator and macOS previews, see the <.localized_link href="/guides/features/previews/run/macos">Tuist macOS companion app instructions</.localized_link>. Physical-device applications remain ineligible for Once publication.
