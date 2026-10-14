# Tuist Cargo compilation cache

Internal implementation of `tuist cargo` caching. Tuist ships the native helper;
developers do not install or invoke a separate cache application.

The complete copied model retains discovered-input validation, local CAS and
action storage, Cargo/Rust/C/C++ compilation handling, build-script modeling,
predictions, bounded speculative prefetching, verification and safe bypasses.
See `NOTICE` and `LICENSE` for source provenance and license terms.

Remote objects use Kura's existing Bazel Remote Execution API. The native client's
algorithm-tagged local identities are indexed by genuine SHA-256 Command/Action
messages; content is stored as SHA-256 CAS blobs. Compilation results publish
complete output-graph references through Action Cache only after CAS publication.
Prediction updates are speculative and last-writer-wins, not compare-and-swap.
Standard REAPI does not supply compilation promises or the copied model's custom
pack extensions; ordinary verified transfers remain available without them.

There is no `[cargo]` configuration section. `tuist.toml` supplies the existing
project/server/network settings. Missing or incompatible helpers use ordinary
Cargo; remote failure leaves local caching and compilation available. Credentials
are private, refreshed, project-scoped and absent from analytics. Transport honors
existing certificate/proxy settings, uses authenticated CONNECT when needed,
and bounds transfers, resumed reads and failed-read time.

The CLI also collects bounded public inspection records for the dashboard's
Cacheable Tasks and CAS Outputs views. These are observed decisions and remote
CAS operations, not private agent events or reconstructed aggregate rows. Keys
retain algorithm tags, closure references come from existing REAPI responses,
and local restores never invent remote transfers. Cache-agent store timings do
not measure completion of background publication. Partial capture is explicit.

## Development

```sh
cargo build --locked --manifest-path cli/native/cargo-cache/Cargo.toml \
  -p tuist-cargo-cache --bin tuist-cargo-cache
cargo test --locked --manifest-path cli/native/cargo-cache/Cargo.toml \
  -p tuist-cargo-cache-core --lib remote_reapi
cargo test --locked --manifest-path cli/native/cargo-cache/Cargo.toml \
  -p tuist-cargo-cache --test tuist_runtime
```

The optional `model-tests` feature builds a fixture-only
`tuist-cargo-cache-model` executable for retained model integration tests. It is
not shipped or selected by `tuist cargo`.

See [model parity and qualification](PARITY.md) for the pinned comparison,
independent audit, corrected integration regressions and deliberate differences.

The runtime and transport remain experimental. Executable/link restores are
bypassed while a macOS verification divergence is investigated. Do not treat
aggregate hit counts, estimated avoided compiler work or one successful fixture
as proof of cross-worker correctness or measured wall-clock savings.
