# Atlas mobile build action

This composite owns shared setup and one `operation` (`build` or `test`) for
trusted and fork jobs in `../../workflows/atlas-mobile.yml`. Do not combine the
operations: the pipeline exposes independent build and test jobs. Lint jobs live
directly in that same workflow. Keep permission decisions in the workflow:
`authenticated` only enables login, it never grants OIDC permissions.

- Run Once from `atlas-mobile/`, which is an independent workspace and has its
  own `tuist/atlas-mobile` cache identity. Do not add it to the root Atlas graph.
- Install only the tools used by the selected platform. Linux needs Once's ALSA
  runtime library and the pinned Android SDK/NDK packages.
- Cache authentication may fall back to local execution; preview publication in
  the workflow must fail visibly if authentication or upload fails.
- Upload only the APK or simulator ZIP plus test reports, never the whole Once
  state directory, credential directories, or debug keystore.
- Validate changes with `actionlint .github/workflows/atlas-mobile.yml` and the
  commands in `atlas-mobile/AGENTS.md`.
