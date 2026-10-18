# Install action

Source for the standalone `tuist/install` composite action. See
`../../workflows/install-action.yml` for tests, packaging, and manual release.

- Compose `tuist/cache-volume@v1`; do not implement mounts or publication policy.
- Keep package discovery aligned with TuistRootDirectoryLocator and
  ManifestFilesLocator. Prefer Tuist/Package.swift, retain package-relative .build,
  and explicitly pass scratch/cache paths. Reject SWIFTPM_BUILD_DIR overrides.
- Inputs reach scripts through quoted environment variables. Never eval them.
- Default keys include job, actual toolchain, relative package path and manifest
  contents; never checkout location, lockfile or volatile CI metadata.
- Always force pinned installation, including hits and forks. Publication is a
  server decision; snapshots must contain only contributor-readable data.
- Keep distributions self-contained and never install/upgrade the CLI here.
- Validate with `node --test .github/actions/install/action.test.mjs`, ShellCheck,
  and actionlint. Tests stub external tools and do not demonstrate live mounts.
