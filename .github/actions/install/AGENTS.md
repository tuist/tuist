# Install action

Source for the standalone `tuist/install` composite action. See
`../../workflows/install-action.yml` for tests, packaging, and manual release.

- Select automatically: `tuist-cache-volume` on PATH or /__e uses volumes; otherwise
  compose `actions/cache@v4`. No backend input. Never archive mounted paths or
  convert volume failures into a second cache attempt. Do not implement mounts.
- Keep package discovery aligned with TuistRootDirectoryLocator and
  ManifestFilesLocator. Prefer Tuist/Package.swift, retain package-relative .build,
  and explicitly pass scratch/cache paths. Reject SWIFTPM_BUILD_DIR overrides.
- Inputs reach scripts through quoted environment variables. Never eval them.
- Default keys include job, actual toolchain, relative package path and manifest
  contents; never checkout location or volatile CI metadata. Volume keys exclude
  lockfiles. Archive keys append platform/architecture and lockfile hash, with a
  compatible restore prefix; keep archive paths relative and escape glob syntax.
- Always force pinned installation, including hits and forks. Publication is a
  server decision; snapshots must contain only contributor-readable data.
- Keep distributions self-contained and never install/upgrade the CLI here.
- Validate with `node --test .github/actions/install/action.test.mjs`, ShellCheck,
  and actionlint. Tests stub external tools and do not demonstrate live mounts.
