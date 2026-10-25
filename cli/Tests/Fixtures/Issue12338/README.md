# Issue 12338 reproducer

Reproducer for [Missing SPM traits in tuist generated xcodeproject from Registry Style](https://github.com/tuist/tuist/issues/12338).

`Tuist/Package.swift` declares `swift-dependencies` by URL with four SPM traits
(`Clocks`, `CombineSchedulers`, `Foundation`, `FoundationNetworking`). `Tuist.swift`
passes `--replace-scm-with-registry` to the installer, so SwiftPM resolves the package
from the registry and its scoped identity (`pointfreeco.swift-dependencies`).
Before the fix, the generated dependency project's `Dependencies` target loses the
`SWIFT_ACTIVE_COMPILATION_CONDITIONS` that traits turn on.

## Run

```bash
./reproduce.sh /path/to/tuist
```

The script copies `Project/` into a temporary directory, runs `tuist registry setup`,
`tuist install`, and `tuist generate --no-open`, then inspects the generated
dependency project for `CombineSchedulers`. It exits non-zero when the traits are
missing, which is what a build without the fix does.

Use the `tuist` binary built from the branch to see the fix, and a release without the
fix (for example `4.213.0-canary.5`) to reproduce the bug.

## Expected results

| Binary | Result |
| --- | --- |
| Without the fix (for example `4.213.0-canary.5`) | `FAIL: ... missing the swift-dependencies traits` |
| With the fix (`xcodebuild build -workspace Tuist.xcworkspace -scheme tuist`) | `PASS: the swift-dependencies traits made it into the generated project` |
