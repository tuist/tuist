# TuistCI

- CI detection is purely environment-variable based.
- Keep this module cross-platform. Cargo reporting and compile-once sharding use it on Linux as well as macOS, so its SwiftPM target belongs in the shared target list.
- `ciInfo()` names only the providers listed here. Whether a run is CI is `Environment.isCI` (a `CI` variable among others), which is how `tuist test`, Cargo, the Gradle plugin and `tuist_ex` report `is_ci`: a run on a CI system Tuist doesn't detect is a CI run without a provider, and the server's flaky detection and CI filters key on `is_ci` alone. Add a provider only together with the server's support (`Tuist.Tests.valid_ci_providers/0`, `Tuist.Builds.valid_ci_providers/0`) and the regenerated client: the generated `ci_provider` enum and an older server's request validation both refuse an unknown value, which loses the run.
