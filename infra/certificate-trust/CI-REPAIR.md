# Aggregate PR CI repair, 2026-10-26

This is source and CI evidence for PR #14511, not permission to merge it,
publish independently distributed clients, or deploy the mitigation. Aggregate
current-head CI must be checked separately. Kura's unresolved resource budgets
and all installed-client/fleet gates remain open.

## Main integration

The branch incorporated main through `d416def414`, preserving main's retry,
connection management, feature, migration and infrastructure changes alongside
certificate enforcement. In particular:

- Cargo archive transfers retain `RetryingURLTransfer` with `.tuistDefault`.
- CAS reconnects reuse the protected endpoint instead of constructing default TLS.
- Atlas's new blocking Automation watches and Orbit live connections explicitly
  use the protected Rustls connectors and private terminal TLS diagnostics.
- Gradle retains native trust enforcement alongside main's retries and pooling.
- TuistEx retains native TLS options alongside configurable request timeouts.
- The rack-switch controller retains Go 1.26.10 and its compatibility default
  alongside main's new PicOS code/dependencies.

The bounded Atlas source guard now scans entire Rust source files rather than
silently ignoring production items after the first test-only item. It inventories
the three WSS factories and rejects default/missing connectors. This is not a
Rust alias, macro or data-flow proof, nor wire qualification of every feature.

## Genuine CI repairs

- The TuistHTTP test target explicitly depends on TuistTestSupport.
- `tuist install` regenerated the manifest origin hash without changing the
  resolved dependency pins. The local invocation required a matched Xcode
  compiler/SDK in the child process; no global Xcode selection changed.
- The standalone SwifterPM Bazel entry point establishes HOME/XDG_CACHE_HOME
  inside TEST_TMPDIR before parallel tests begin, without inheriting host
  credentials or mutating individual tests' environments. This does not repair
  multi-Xcode framework selection on the developer host.
- The Linux bind-mount test container receives the public incident fixture
  directory read-only. The test binary alone did not contain those files.
- Orbit session fixtures gate tests sharing the production eight-handle registry
  for their libtest worker lifetime, without increasing the production limit.
- TuistEx's merged HTTP timeout options were formatted with its formatter.

## OTP alternate-path root cause and correction

Server run [40298720973](https://github.com/tuist/tuist/actions/runs/40298720973),
job 121491060692, failed its credential-free preflight. Both controls loaded
120 native roots, including GTS Root R4. Native TLS accepted; the protected
callback failed with `unknown_ca`. This rules out blaming an absent Google
anchor or assuming both native and protected verification failed in that run.

OTP's `public_key:pkix_path_validation/3` handles an initially unknown issuer by
calling the verifier directly and returning its failure reason without wrapping
it. `ssl_handshake` recognizes `{error, {bad_cert, unknown_ca}}` to search
alternate/cross-signed paths. Our callback incorrectly returned only the inner
`unknown_ca`, preventing that native repair and producing a generic handshake
failure. It now preserves the complete `{:bad_cert, reason}` failure. It never
accepts an unknown CA or changes the native root set.

The synthetic cross-sign test serves a root cross-signed by an absent issuer,
while the client trusts its self-signed version. Native and protected OTP/Mint
accept, and an unrelated anchor rejects. Direct OTP rejects the old stripped
callback; Mint may resolve the alternate anchor before that branch. The initial
attempt to require a legacy failure on Mint too was incorrect and is not passing
evidence. Direct PKIX error-shape assertions cover the native classification.

At `e872261b20`, server run
[40300404301](https://github.com/tuist/tuist/actions/runs/40300404301), job
121496711045, passed Build Test Shards: native/protected TLS both accepted with
the same 120 roots, protected credential-free HTTP completed (406 is an HTTP
response, not a TLS failure), and subsequent authenticated compilation/shard
planning completed. This selected job is not aggregate CI clearance. The
TuistEx job at that source still failed the overbroad Mint legacy-negative test;
the corrected test must be qualified on the next source revision.

The preflight is an explicit credential-free opt-in before authentication,
reports fixed outcomes/root counts, and never falls back to native-only TLS for
credentials. It diagnoses the observed failing Tuist OIDC leg, not every OIDC
provider or runner pool.

## Local validation

- Generated Xcode workspace, focused TuistHTTP/REAPI tests: 86 and 6 Swift Testing
  cases passed. Cargo source compiled; the selected Cargo suite ran no cases,
  so this is not Cargo runtime test evidence.
- Atlas Rust workspace: 117 auth, six CLI and twelve navigation cases passed;
  workspace/all-targets Clippy passed with warnings denied.
- Standalone SwifterPM matched-Xcode Bazel runner: 355 tests / 28 suites passed
  in 64.425 seconds. This is local test-process qualification, not a signed CLI.
- Corrected TuistEx certificate/HTTP/auth suites: 37 passed; the cross-sign
  regression also passed ten independent seeded invocations.
- Genuine Go 1.26.10 shared policy/store/factory suite passed, including the
  tightened Atlas inventory and its regression fixtures.

Current-head PR checks, exact artifacts/minimum runtimes and deployment gates
must still be evaluated independently. No later production/customer publication
or rollout occurred as part of this CI work.
