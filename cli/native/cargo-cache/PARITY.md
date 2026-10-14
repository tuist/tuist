# Cargo cache model parity and qualification

## Comparison baseline

The owned model is copied from Mr. Boxington 1.23.0, revision
`882378d6e7cadfef84cce21e25939bf3bbae6d00`. LICENSE and NOTICE retain provenance;
Tuist package names and settings do not change the model versions.

The October 2026 review compared all seven source packages against that pinned
checkout, including an independent read-only Claude review of the application,
Swift integration and REAPI adapter. The initial name-normalized source inventory found
92 equivalent files and 66 changed files. This inventory is useful for locating
changes, not proof of behavioral parity. The independent review is a source
audit, not production correctness or performance certification.

Upstream HEAD was also checked at
`db98a2ce9d5f1848596b18d140d9e0a5aecce3ec`. Its intervening runtime change corrects
nextest `--jobs` versus `--build-jobs` interpretation and aliases for the copied
application's scheduler. Tuist disables that scheduler; this later change is
not claimed as part of the pinned model. The other intervening change is CI
configuration.

## Preserved model

| Boundary | Preserved behavior |
| --- | --- |
| Core | Discovered-input snapshots and validation, action identity, predictions, prefetching, shadow verification, input mutation rejection, output materialization and safe misses. |
| Rust compiler | Compiler identity, rustc arguments/response files, dep-info and environment dependencies, build-script/proc-macro inputs, artifact relationships and eligibility/bypass decisions. |
| C/C++ | Copied compiler interception, input discovery, object caching and invalidation machinery. |
| Cargo | Workspace/toolchain/target discovery, prediction selection, nested Cargo session boundaries and original argument forwarding. |
| Local store | Algorithm-tagged CAS, action indexes, manifests, reachable output trees, bounded history, collection and verification. |
| Protocol | Private session protocol and coordinated compiler requests. |
| Application | Session coordination, verification, cleanup, compiler streaming and bounded public statistics. Standalone application commands and model-only fixtures remain source, not public Tuist commands. |

Cargo freshness remains Cargo's responsibility. A prediction or lockfile never
proves a hit: discovered inputs and required outputs must validate. Actual
compiler executions are observed; restores and successful opaque wrappers are
not invented compiler rows.

## Deliberate integration differences

- The only public command is `tuist cargo`. The bundled `tuist-cargo-cache`
  sibling is mandatory in releases, protocol checked and never resolved from an
  independent installation. Model-only integration fixtures do not ship.
- Project/server/network configuration comes from `tuist.toml` and existing Tuist
  services. Independent model global/workspace configuration is ignored,
  including automatic and low-disk cleanup. No `[cargo]` section is required.
- Target placement/views, lanes, seeding, scheduler-driven execution, learned
  incremental rewriting, first-run notices and application summaries are
  disabled for transparent Cargo decoration. Existing global compiler wrappers
  disable caching/observation; empty wrappers mean no wrapper. Workspace
  wrappers remain authoritative and must not become false compiler observations.
- Executable/link restores remain disabled because the retained macOS shadow
  verification divergence is unresolved. Eligible library caching is
  experimental; expected executable output does not establish link-cache
  correctness.
- Kura's existing REAPI replaces the model's custom remote transport. Local
  identities remain algorithm-tagged BLAKE3. Remote CAS blobs and serialized
  Command/Action indexes use genuine SHA-256. A complete verified output closure
  must be uploaded before publishing an Action Cache index.
- Standard REAPI does not provide the model's atomic conditional prediction
  writes, global CAS, promise ownership or pack extensions. Predictions are
  advisory last-writer-wins; unsupported optimizations fall back. Lost prediction
  updates may reduce hits but cannot authorize an unvalidated restore.
- Remote publication retains protected-branch CI-push eligibility. Ordinary
  local invocations are not implicitly authorized publishers. Changing this
  policy requires an explicit decision, not a parity fix.
- Reports contain a bounded allowlist, not private agent events, credentials or
  arbitrary compiler arguments. Aggregate hits do not establish local/remote
  attribution; transfers can include speculative prefetches; cumulative phases
  can overlap; estimated compiler work is not measured wall-clock savings.

## Regressions corrected by the comparison

- Automatic cleanup previously re-entered the shipped helper as `gc --automatic`,
  which was forwarded to Cargo. It now uses the private
  `__tuist_gc_automatic` entry with Tuist-only configuration. A shipped-entry test
  proves that an old CAS object is collected without invoking Cargo.
- Unary REAPI requests incorrectly inherited the long overall transfer timeout.
  They now use the read timeout with an outer bound that covers channel readiness,
  request construction and the RPC. Streaming bounds its initial request and
  each stalled read while retaining an overall transfer deadline; HTTP/2 keepalive detects unresponsive peers. A hanging TCP-peer test
  checks the bound.
- ByteStream publication lacked retries. Transient writes now retry with fresh
  upload resources and CAS presence checks, bounded by attempt count and the
  overall transfer deadline. Unary/write admission retries honor bounded
  `google.rpc.RetryInfo`; permanent failures do not retry. Kura does not retain
  partial writes for resumable uploads.
- Streamed reads previously advanced the digest and offset before the local write
  succeeded. They now advance only after success; local I/O failures terminate
  instead of resuming into a partial destination. Missing/corrupt objects remain
  misses, never hits.
- Setup errors after initial configuration could fail before Cargo ran. Native
  setup now falls back only before a successful Cargo spawn; post-spawn errors
  cannot rerun work. Remote construction failures preserve local caching.
- Bypassed compiler execution recorded timing/status without diagnostics. With an
  invocation-local observer, stderr is forwarded live while at most 2 MiB is
  retained for diagnostic extraction. Queries and absent observers retain direct
  execution. A real incremental workspace warning tests the shipped helper.
- The model's plain-output preference forced Cargo progress off. Native mode now
  preserves Cargo's own progress environment. Empty global wrapper values no
  longer masquerade as configured wrappers.

## Remaining limits and required evidence

This comparison is not a claim that nothing can be missing. In particular:

- Diagnose the executable divergence before enabling link restores.
- Qualify genuinely independent workers, toolchains, SDKs, source/feature changes
  and undeclared build-script/proc-macro inputs.
- Expand real REAPI failure tests for corrupt/evicted recursive closures,
  concurrent publication, dropped acknowledgments, interrupted uploads, resumed
  reads, cancellation, token refresh and certificate/proxy combinations.
- Publication currently resolves some output closure information through remote
  reads even when compilation produced those objects locally. This can add RTTs
  and make publication dependent on read availability. Avoid claiming equivalent
  remote efficiency until local closure hints/batching are designed and measured.
- Measure sustained client/Kura CPU, memory, disk and network use, admission,
  draining, replication/durability and useful versus wasted speculative transfers.
- Validate actual signed/notarized universal macOS and both static musl Linux
  bundles, and broaden TTY/jobserver/signal/custom-Cargo/nextest regressions with
  bundled caching enabled.
- Demonstrate endpoint discovery without the explicit override used by the
  existing single-Mac remote-cache E2E.

Retained model integration tests are necessary but do not exercise the shipped
entry. Run `--test tuist_runtime` without `model-tests` as well as workspace
library tests, model fixtures and actual `tuist cargo` scenarios. Do not broaden
public support claims from build success, a source inventory or one-host hits.
