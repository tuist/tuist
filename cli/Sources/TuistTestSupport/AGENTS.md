# TuistTestSupport

Lightweight, cross-platform checkout paths and snapshot assertions for tests. Keep this module independent of CLI production modules and the larger `TuistTesting` infrastructure.

- Read the real checkout from the process's `TUIST_CONFIG_SRCROOT`, supplied by test schemes. SwiftPM tests without that variable discover the checkout from their working directory.
- Use `TestPaths.fixturesDirectory` and `TestPaths.examplesDirectory` for checked-in test inputs. Do not use compiler source locations as filesystem paths.
- Use `assertRepositorySnapshot` for file-backed snapshots. It resolves Xcode's `/^src` paths against the runtime checkout while preserving snapshot naming, recording behavior, and assertion locations.
- Test resolution with explicit environment dictionaries and temporary directories; never mutate the process environment.
