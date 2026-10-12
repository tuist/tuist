# Atlas native build and test action

This composite owns shared setup and one `operation` (`build` or `test`) for
trusted and fork jobs in `../../workflows/atlas-mobile.yml`. Do not combine the
operations: the pipeline exposes independent build and test jobs. Lint jobs live
directly in that same workflow. Keep permission decisions in the workflow:
`authenticated` only enables login, it never grants OIDC permissions.

- Run Once from `atlas-native/`, which is an independent workspace and retains
  the `tuist/atlas-mobile` cache identity. Do not add it to the root Atlas graph.
- Install only the tools used by the selected platform. Linux needs Once's ALSA
  runtime library. Only Android/iOS need Rust cross-compilation standard
  libraries; CLI and core tests use the host toolchain.
- Cache authentication may fall back to local execution; preview publication in
  the workflow must fail visibly if authentication or upload fails.
- Upload only platform artifacts and test reports, never the whole Once state
  directory, credential directories, or debug keystore. Archive the CLI with tar
  so GitHub artifact extraction does not remove its executable permission.
- The CLI is a command-line artifact, not an Android/iOS preview. Keep its artifact
  name labeled with the build host OS and architecture.
- Validate changes with `actionlint .github/workflows/atlas-mobile.yml` and the
  commands in `atlas-native/AGENTS.md`.
