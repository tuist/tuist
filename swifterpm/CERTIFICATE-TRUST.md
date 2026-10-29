# Standalone certificate trust

This extracts standalone SwifterPM's Apple Foundation hardening from
[tuist/tuist#14511](https://github.com/tuist/tuist/pull/14511), snapshot
`e2efb26eb30c0c7657601c62dd9270551f94f090`. It does not require the CLI's HTTP
or REAPI implementation, root package changes, or runtime policy files.

`CertificateTrust.swift` embeds the snapshot's
[twelve SHA-256 SPKI hashes](https://github.com/tuist/tuist/blob/e2efb26eb30c0c7657601c62dd9270551f94f090/infra/certificate-trust/policy.json).
The Apple URLSession delegate first requires ordinary native trust evaluation,
then rejects any denied key in the complete evaluated chain, including issuers
and anchors constructed by Security.framework. It does not replace system or
enterprise roots, weaken hostname/expiry/signature checks, or change host trust.
Additional fixture anchors are session-local; additional denies are add-only.

## Failures must reach the command

- `HTTPClient` does not retry TLS failures. Cancellation during retry backoff
  throws instead of starting another request.
- Provider version metadata can fall back to Git for ordinary errors, but TLS
  and cancellation escape before Git or an empty version list can be cached.
- `ensureSource` checks archive errors before resetting its temporary directory
  and fetching Git. TLS/cancellation leave no source revision marker or published
  source directory. Its outer catch removes the temporary directory and rethrows.
- `restoreSourcePins` adds package context to errors. The resulting `ToolError`
  loses the original typed classification, but `restorePackage`, public
  `SwifterPM.restore/resolve/update`, and the standalone CLI do not catch it to
  retry native resolution. The CLI exits with failure. Embedders must not add an
  unconditional native fallback around those public calls.
- Registry archive errors cannot return a concurrently populated cache entry
  after TLS/cancellation. Native registry checksum seeding also propagates these
  errors even after native resolution succeeds, preserving the native download
  without publishing an unchecked cache entry. Ordinary unavailable metadata
  remains best effort.

This is a source-level caller assessment, not wire qualification of a complete
provider archive-to-Git flow. In the current Tuist caller,
`SwiftPackageManagerController.resolve/update` also propagate SwifterPM errors;
native resolution is an explicit configuration choice, not an error fallback.
That embedded caller is outside this standalone PR's validation scope.

## Tests and isolation

The standalone Bazel target includes the policy and PEM fixtures through existing
source/data globs. No root manifest changes are needed. The test entry point
creates HOME/XDG_CACHE_HOME under TEST_TMPDIR before parallel test execution.
Individual tests must not mutate the process environment or use personal caches.
The loopback TLS fixture needs Homebrew OpenSSL 3; LibreSSL cannot bind its server
to a single interface. CI installs that dependency for the unit-test job.

The tests distinguish real policy-key hashing from application enforcement:
public endpoints may already fail native trust. Only otherwise-accepted private
chains with add-only denies demonstrate that the application restriction runs.
Unknown roots, wrong hostnames, expired and invalidly signed certificates must
still fail ordinary native verification. Public production HTTP data/download
controls are opt-in with `SWIFTERPM_TRUST_LIVE=1`.

On a multi-Xcode Mac, match the selected compiler, SDK and loaded Testing
framework per process. Do not change global Xcode selection or shut down shared
Bazel servers. From `swifterpm/`, the isolated qualification command is:

```sh
qualification="$PWD/.build/certificate-trust"
mkdir -p "$qualification"
cat > "$qualification/matched-xcode-runner.sh" <<'SH'
#!/bin/bash
set -euo pipefail
unset TOOLCHAINS SDKROOT SWIFT_EXEC SWIFT_DRIVER_SWIFT_FRONTEND_EXEC
export DEVELOPER_DIR=/Applications/Xcode-27.2.app/Contents/Developer
export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
export DYLD_FRAMEWORK_PATH="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/Library/Frameworks"
export DYLD_LIBRARY_PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx:$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/usr/lib"
exec "$@"
SH
chmod +x "$qualification/matched-xcode-runner.sh"
DEVELOPER_DIR=/Applications/Xcode-27.2.app/Contents/Developer \
  "$(mise which bazel)" --batch \
  --output_user_root="$qualification/bazel-user" \
  --output_base="$qualification/bazel-output" --host_jvm_args=-Xmx2g \
  test //:swifterpm_tests --lockfile_mode=off --xcode_version=27.2 --jobs=2 \
  --repository_cache="$qualification/bazel-repository" \
  --disk_cache="$qualification/bazel-disk" \
  --nocache_test_results --test_output=all --test_env=SWIFTERPM_TRUST_LIVE=1 \
  --run_under="$qualification/matched-xcode-runner.sh"
```

The extraction's actual local run used the same flags with qualification files
under the worktree's ignored `.amp/in/` directory instead of `.build/`.
This host-specific runner repairs multi-Xcode loading for qualification; it is
not a portable CI fix or a change to production environment handling.

## Local validation receipt

On 2026-10-27, macOS 27.0 arm64, Bazel 8.7.0, Xcode 27.2 (27B5019j), Apple
Swift 6.4 and OpenSSL 3.6.4: the actual `//:swifterpm_tests` Bazel target passed
**356 tests in 28 suites in 67.278 seconds**, with public controls enabled and
test-result reuse disabled. The private fixture covers accepted leaf,
intermediate and root denies through data/download/redirect, followed by restored
positive transfers. Native verification failures, registry metadata/seeding
propagation and cancellation during retry backoff also passed.

`bazel build //:swifterpm` passed with the same isolation and two-job flags; the
built executable's `--help` exited successfully under a disposable HOME. This
was not a signed release build or a CLI wire test. Scoped actionlint 1.7.12 with
ShellCheck 0.11.0 passed after ignoring only the existing custom
`tuist-macos-27-0` runner-label diagnostic. `git diff --check` passed. The broad
shell E2E task, Linux and minimum-runtime matrix were not run locally.

## Remaining qualification and release gates

- Exercise full provider archive-to-Git and registry archive-download failure
  flows, including cancellation and a fallback that would otherwise succeed.
  Helper tests and source inspection do not close these integration gates.
- Linux FoundationNetworking has no application deny enforcement from this
  Apple delegate. Its verifier/runtime requires a separate implementation and
  qualification. Do not describe Linux as protected by this change.
- External Git, native SwiftPM, Bazel downloads and other delegated tools own
  their trust independently. This PR does not harden or qualify them.
- Run the focused PR's CI and qualify supported minimum macOS/toolchain versions,
  exact signed standalone release artifacts and installed-client replacement
  through the standalone owner pipeline. Local tests are not release evidence.
- Root manifests, generated Tuist test-source lists and CLI HTTP/REAPI changes
  belong to separate owners. They are not prerequisites for standalone Bazel
  tests and are not qualified here.

Keep the extraction PR draft while material qualification gates remain open.
No merge, release, installed-client replacement or deployment is authorized by
this work.
