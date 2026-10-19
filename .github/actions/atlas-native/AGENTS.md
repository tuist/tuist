# Atlas native build and test action

This composite owns shared setup and one `operation` (`build` or `test`) for
trusted and fork jobs in `../../workflows/atlas-mobile.yml`. Do not combine the
operations: the pipeline exposes independent build and test jobs. Lint jobs live
directly in that same workflow. Keep permission decisions in the workflow:
`authenticated` only enables login, it never grants OIDC permissions.

- Run Once from `atlas-native/`, which is an independent workspace and retains
  the `tuist/atlas-mobile` cache identity. Do not add it to the root Atlas graph.
- The pipeline sets `MISE_AUTO_INSTALL=0`: every job must explicitly install its
  tool subset. Without it, `mise exec` and `mise run` install the entire inherited
  monorepo tool set, even for Rust-only jobs.
- Initialize Android command-line tools with `android-actions/setup-android`
  before invoking `sdkmanager`; hosted images do not put it on PATH by default.
  Request `platform-tools` explicitly, not the retired default `tools` package.
- Generate an ephemeral Android debug keystore and export
  `ANDROID_DEBUG_KEYSTORE`; Once does not create a key automatically on clean
  runners. The standard public debug password is `android`, not a secret.
- Materialize locked Cargo sources with `mise run prepare:rust` before validating
  the Once graph. Core tests include the independent Rust authentication suite;
  upload its normalized reports alongside the navigation reports.
- Install only the tools used by the selected platform. Linux needs Once's ALSA
  runtime library. Only Android/iOS need Rust cross-compilation standard
  libraries; CLI and core tests use the host toolchain.
- Cache authentication may fall back to local execution; preview publication in
  the workflow must fail visibly if authentication or upload fails.
- Upload only platform artifacts and test reports, never the whole Once state
  directory, credential directories, or debug keystore. Archive the CLI with tar
  so GitHub artifact extraction does not remove its executable permission.
- `ios-device` builds `AtlasIOSDevice` with `aarch64-apple-ios` dependencies and
  uploads a device ZIP without distribution credentials. The workflow's protected
  main-branch publication job owns signing, not this shared PR/fork action.
- The CLI is a command-line artifact, not an Android/iOS preview. Keep its artifact
  name labeled with the build host OS and architecture.
- Validate changes with `actionlint .github/workflows/atlas-mobile.yml` and the
  commands in `atlas-native/AGENTS.md`.
