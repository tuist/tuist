# Standalone SwifterPM qualification

SwifterPM's Apple Foundation client independently embeds the twelve-key policy.
It retains ordinary native verification and checks the complete evaluated chain,
including constructed issuers and anchors. TLS failures and cancellation must
escape archive/metadata optimizations rather than falling back to Git or silently
publishing unchecked cache entries. See the C10 row in [CLIENTS.md](CLIENTS.md).

## Completed Bazel suite

Source `f5a0bccccdfe41e2df59ce1e29a0e54a41adf84b`, Bazel 8.7.0, Xcode 27.2,
macOS arm64: **355 tests in 28 suites passed in 56.086 seconds**. The actual
`bazel test //:swifterpm_tests` target passed, not just a directly launched binary.
`SWIFTERPM_TRUST_LIVE=1` was enabled: the production HTTP data/download public
controls ran and passed. Real incident DER, accepted private-root/leaf add-only
negative differentials, normal native failures, registry propagation and
production delegate wiring remain distinct assertions; public OS rejection alone
does not establish application-policy execution.

This supersedes the earlier claim that the independent Bazel suite could not
reach discovery. The earlier generated-core Xcode 26.6 result (287 tests in 17
suites) remains separate evidence, not the size of this broader current suite.

## Discovery and environment diagnosis

The test binary's runtime paths search global developer-directory links before
its selected Xcode 27.2 framework path. On this host the global links resolve to
Xcode.app 26.6. With the same diagnostic binary:

- Default framework loading selects 26.6's `Testing.framework` and discovery
  exits with signal 11.
- Explicit per-process framework selection loads 27.2's `Testing.framework` and
  discovery completes. Dynamic-loader logs identify the actual loaded paths.

A first current-tree run with matching frameworks reached all tests but had three
failures: no HOME for the default cache-root test, and two manifest tests selecting
an ambient standalone Swift 6.3.2 compiler against the 27.2 SDK. Those compiler
failures included `unknown argument: '-target-arch-variant'`. A test-private HOME
and an explicitly matching compiler PATH resolved these without source changes.

The passing invocation was:

```sh
bazel test //:swifterpm_tests --lockfile_mode=off --xcode_version=27.2 --jobs=6 \
  --nocache_test_results --test_output=all --test_env=SWIFTERPM_TRUST_LIVE=1 \
  --run_under=/tmp/tuist-emudhra-audit/swifterpm-bazel-matched-runner.sh
```

That qualification-only shell runner creates `HOME` and `XDG_CACHE_HOME` beneath
Bazel's `TEST_TMPDIR`, unsets ambient `TOOLCHAINS`, `SDKROOT`, `SWIFT_EXEC` and
`SWIFT_DRIVER_SWIFT_FRONTEND_EXEC`, and sets `DEVELOPER_DIR`, compiler PATH,
`DYLD_FRAMEWORK_PATH` and `DYLD_LIBRARY_PATH` to the explicitly selected Xcode.
It retains the existing Homebrew OpenSSL 3 loopback fixture dependency. It sets
the loader variables inside the runner, after any system-shell launch, rather
than assuming inherited DYLD variables survive that launch. No global Xcode
selection, Bazel server shutdown, binary modification or host trust change was
used. This is a qualified local invocation, not a portable CI environment fix.

Logs and runner are under `/tmp/tuist-emudhra-audit/`:
`swifterpm-bazel-direct-{default,matched}-discovery.log`,
`swifterpm-bazel-discovery-binary-sha256.txt`,
`swifterpm-bazel-test-{linked-libraries,load-commands}.txt`,
`swifterpm-bazel-current-matched-frameworks.log` (three failures) and
`swifterpm-bazel-current-isolated-matched.log` (complete pass).

## Still separate

- Full registry archive-download catch and provider archive-to-Git TLS-failure
  integration remain helper-level coverage, not closed by the suite total.
- Linux FoundationNetworking has no deny from this Apple delegate. External Git,
  native SwiftPM and Bazel remain independent trust owners.
- This does not execute or qualify the signed standalone CLI release. The older
  Bazel CLI candidate hash identifies that earlier build, not these test bytes.
- No package publication, installed-client replacement, production rollout or
  fleet protection is established by this result.
