# Coverage observer

The library `tuist test` and `tuist xcodebuild test` inject into test hosts to record which coverage counters each test moves: the raw material of per-test coverage evidence (`TuistKit.TestCoverageEvidenceService`, `XCResultParser.TestCoverageEvidence`).

## Files
- `TuistCoverageObserver.m` - the observer. Plain C and Objective-C against Foundation; XCTest is looked up at run time (class, protocol and selectors by name), so the library links against nothing a host may lack. It never calls the LLVM profile runtime (its symbols are hidden per image): it reads each instrumented image's `__llvm_prf_cnts` section directly and never zeroes it, so Xcode's own coverage report is untouched.
- `CoverageAttributionTrait.swift` - the Swift Testing trait users copy into a test target. Swift Testing has no hook an injected library can join, so the trait calls `tuist_coverage_scope_begin/end` (resolved with `dlsym`; a no-op when the observer is not injected). Not compiled into the CLI.
- `build.sh <directory>` - builds `libtuist_coverage_observer.dylib` (macOS) and `libtuist_coverage_observer_iossimulator.dylib`, both universal. `mise/tasks/cli/bundle.sh` ships them next to `tuist`; `TUIST_COVERAGE_OBSERVER_PATH` points the CLI at another directory (a local build).

## Contract with the CLI
- Input: `TUIST_COVERAGE_OBSERVER_DIR` (passed as `TEST_RUNNER_TUIST_COVERAGE_OBSERVER_DIR`). Without it the library does nothing.
- Output, under `<dir>/<pid>/`: `images.tsv`, `<n>.data` and `<n>.names` (raw `__llvm_prf_data` / `__llvm_prf_names`), and `records.bin`, whose layout is documented at `write_record()` and read by `TuistKit.CoverageObserverOutput`. Change both together.
- On the iOS simulator `DYLD_INSERT_LIBRARIES` must also carry Xcode's `libXCTestBundleInject.dylib`, or the host never connects to xcodebuild; the observer registers from the main queue, not from its constructor, for the same host.
- A scope that overlaps another (Swift Testing running in parallel) is flagged and left out of per-test evidence; the target's evidence still holds it.

## Never
- Crash or block the host: every failure path returns and the tests run as if nothing had been injected.
- Reset or write the counters.
