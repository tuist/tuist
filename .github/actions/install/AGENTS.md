# Install action

Source for the standalone `tuist/install` composite action. See
`../../workflows/install-action.yml` for tests, packaging, and automatic main-branch releases.

- Select automatically: `tuist-cache-volume` on PATH or /__e uses volumes; otherwise
  compose `actions/cache@v4`. No backend input. Never archive mounted paths or
  convert volume failures into a second cache attempt. Do not implement mounts.
- Keep package discovery aligned with TuistRootDirectoryLocator and
  ManifestFilesLocator. Prefer Tuist/Package.swift, retain package-relative .build,
  and explicitly pass scratch/cache paths. Reject SWIFTPM_BUILD_DIR overrides.
- Inputs reach scripts through quoted environment variables. Never eval them.
- Default keys are stable names: job plus the relative package path when it is not
  the checkout root. Never include toolchain versions, manifest or lockfile
  contents, checkout location or volatile CI metadata. Archive keys append platform/architecture and lockfile hash, with a
  compatible restore prefix; keep archive paths relative and escape glob syntax.
- Always force pinned installation, including hits and forks. Publication is a
  server decision; snapshots must contain only contributor-readable data.
- Keep distributions self-contained and never install/upgrade the CLI here.
- Validate with `node --test .github/actions/install/action.test.mjs`, ShellCheck,
  and actionlint. Tests stub external tools and do not demonstrate live mounts.
- Releases use the `install-action` component and `install-action@` source tags.
  Keep version calculation, distribution publication, and monorepo recording in
  that order. Recover any unrecorded distribution from its original SOURCE_COMMIT,
  then dispatch queued changes. Never expose release credentials on PR events.
- Run `bash scripts/release_test.sh` with git-cliff and jq for release changes;
  it covers version selection, irrelevant changes, recovery, and stale sources.
