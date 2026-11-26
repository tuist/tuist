# Snapshot commands

`tuist snapshots upload` uploads a directory of recorded snapshot images as a
snapshot build. `tuist test` (generated projects) and `tuist xcodebuild test`
(any Xcode project) both go through `SnapshotsTestRunner`. Without
`--snapshots`/`--no-snapshots` it is on only in CI, for a project with a
`fullHandle`, when the caller doesn't set `TEST_RUNNER_SNAPSHOTS_EXPORT_DIR`
itself, and it uploads only when the run rendered images: local runs would
upload uncommitted changes and fail on them. When on, it exports the images the
[tuist/snapshots](https://github.com/tuist/snapshots) library renders from previews
(`TEST_RUNNER_SNAPSHOTS_EXPORT_DIR`), uploads them through
`SnapshotsUploadService` even when tests fail, and marks the build selective
when the run skipped tests, so missing images count as skipped, not removed.
`tuist snapshots download` writes the baseline an upload from the checkout
would be compared with (the server's `resolve_baseline`), under the same image
names, so in-process verifiers can use it instead of reference images in Git.

- Keep the upload contract aligned with the Gradle plugin's
  `gradle/src/main/kotlin/dev/tuist/gradle/TuistSnapshots.kt`: the same image
  names (paths relative to the directory), derived Roborazzi files skipped,
  Sentry-format JSON sidecars, `tuist-all-image-names.txt`, pull request title
  sources, and the verdicts that fail the command (`needs_review`, `rejected`;
  `failed`, and a build still `processing` when the wait times out, whatever
  `failOnChanges` says).
- While snapshots run, `TestService` hands its selective-testing hashes to
  `SnapshotsTestRunner.hashStoresAwaitingVerdict`, which stores them only once
  the verdict is `passed`, `baseline` or `approved`. A hash stored earlier would
  make a rerun skip the snapshot target, upload nothing and pass unreviewed.
- The server API lives in `server/lib/tuist_web/controllers/api/snapshots_controller.ex`;
  regenerate the OpenAPI client after changing it, never edit it by hand.
- `status` and `state` are open strings: never switch on them exhaustively.
- The merge base comes from the checkout only (no fetching); the server falls
  back to its commit graph and then to the default branch's latest build.
