# Xcode output-transfer autoresearch

## Objective

Reduce transferred compiler-output bytes without changing compiler-visible data,
action validity, or existing-reader compatibility. Continue on the current pull
request branch: app-managed branch creation needs a separate explicit request.

## Metrics and workload

Primary: warm_bytes, lower is better. This offline upper-bound upload experiment
counts chunks absent from the base plus 80 estimated metadata bytes per chunk.
It does not model local-cache eviction, network latency, or duplicated fetches.
Secondary: cold_bytes, metadata_bytes, encode_ms, decode_ms. Reject a cold-size
regression above 5% or an encoding-time increase above 2x without a compelling
measured benefit. Every base and edited frame must round-trip byte-for-byte.

Use named base/edited artifact paths supplied by AUTORESEARCH_FIXTURES: actual
4,000-struct Xcode module/object/dependency/source-info outputs, three historical
ProjectDescription public edits, a generated C object pair, a large standalone
Swift module, and the exploratory precompiled Foundation header. These are not
a representative customer distribution; inspect every case, not just the sum.

## Run

From cas-plugin: `python3 autoresearch.helper.py run --command ./autoresearch.sh`.
Initialize with the skill helper, primary warm_bytes, bytes, lower, and a bounded
eight-experiment segment. Every run includes correctness checks. Record keep or
discard with a hypothesis and result; discarded configuration changes must be
reverted explicitly before logging. Automatic broad reset/clean is disabled.

## Scope and constraints

- Search: examples/chunking_search.rs, autoresearch.config.json, session files.
- Potential production follow-up: src/reapi.rs and focused tests only after a win.
- Transfer chunk parameters and server negotiation stay unchanged.
- Do not ship field transforms/dictionary patches under the existing capability.
- Do not change Swift inputs, toolchain flags, server formats, or compiler keys.
- Benchmark object section parsing stays experimental until bounded tests pass.
- Keep/discard helper commits require inspecting the clean shared worktree.

## What's been tried

- Prior work: whole-stream compression below the transfer threshold avoids 9.2%
  growth in one Swift dependency output. Existing production baseline retained.
- Field-separated dictionary patches improved historical Swift modules, but need
  a separately negotiated codec, full native preparation, and strict resource limits.
- Next: sweep compression chunk sizes/levels, then object section boundaries.
- Separate lead: background and demand reads fetched some large nodes twice in
  the live Xcode check. Investigate shared in-flight reads after this segment.
