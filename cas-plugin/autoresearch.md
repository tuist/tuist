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
Artifacts are framed as reference-free leaves. The inventory established that
the large outputs in these fixtures are opaque nodes; this model does not replace
measuring actual graph structure for another Xcode task or toolchain.

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
- Completed the eight-run segment on 2026-09-08. The table below preserves all
  decisions. The checked-in configuration is a research candidate, not a change
  to the production encoder.

| Raw average, compression level, section resets | Warm bytes including estimated metadata | Cold payload bytes | Decision |
| --- | ---: | ---: | --- |
| 512 kibibytes, 1, off | 50,368,290 | 60,615,810 | Baseline |
| 128 kibibytes, 1, off | 51,240,657 | 61,282,171 | Discard |
| 64 kibibytes, 1, off | 51,873,554 | 61,495,289 | Discard |
| 1 mebibyte, 1, off | 54,045,186 | 60,416,460 | Discard |
| 512 kibibytes, 1, on | 49,778,406 | 60,604,770 | Keep for research only |
| 512 kibibytes, 3, on | 52,119,644 | 59,253,654 | Discard |
| 256 kibibytes, 1, on | 49,897,967 | 60,973,732 | Discard against best candidate |
| 128 kibibytes, 1, on | 51,753,469 | 61,259,078 | Discard |

Section resets use the 64-bit little-endian object-file section and relocation
ranges from Apple's [Mach object-file definitions](https://github.com/apple-oss-distributions/cctools/blob/main/include/mach-o/loader.h).
Bytes and offsets never change. Unrecognized or invalid layouts fall back to
ordinary boundaries. Transfer chunk parameters stay fixed for every experiment.

The retained candidate lowered the C object's warm payload from 2,001,189 to
1,518,345 bytes (24.1%) and the Swift object's from 10,920,468 to 10,813,428
(0.98%). Other fixtures were unchanged. Aggregate improvement was 1.17%, not
enough evidence to add a production parser. In particular, smaller compression
frames and stronger compression were not monotonically better for reuse.

All eight configurations restored every frame exactly. Byte totals are
deterministic, not noisy timing estimates. The initial timing entries in the
journal are single observations. Confirmation runs now sum per-pair medians of
three encoding and decoding samples, also checking deterministic encoded bytes.
The baseline example test verifies the benchmark matches the production encoder,
including nodes with references and below-threshold fallback.

Confirmation preserved the exact byte totals. Summed per-pair median encoding
was 564.4 milliseconds for the baseline and 619.8 for the section candidate;
decoding was 235.8 and 264.2 milliseconds. These short local timing samples are
noisy and are not evidence of a speedup. The candidate trades somewhat more
observed work for a small aggregate byte saving, another reason not to ship it yet.

## Reproduction and resumption

Build actual outputs using `../kura/test/e2e/xcode_chunking_check.py` and the
fixture generators linked in `../kura/docs/client-chunking.md`. Supply a JSON
array with entries such as
`{"name":"swift_object","base":"/path/to/base/Fixture.o","edited":"/path/to/edited/Fixture.o"}`.
Set `AUTORESEARCH_FIXTURES` to that manifest and run `./autoresearch.sh` and
`./autoresearch.checks.sh`. Paths are external so compiler outputs and local
temporary directories are not committed. The complete historical ten-pair corpus
is not bundled; a newly generated corpus is a new baseline, not a reproduction of
the exact byte totals above. `AUTORESEARCH_CONFIG` optionally selects another
configuration file. The baseline is
`{"average":524288,"level":1,"sections":false}`.

The optional helper wrapper uses the installed autoresearch skill and disables
its broad worktree reset. It still auto-commits kept runs, so inspect the entire
worktree before logging. The segment has reached its eight-run limit. Resume with
a new bounded segment rather than silently extending it or mixing metrics.

## Separate production follow-up: shared active downloads

The real Xcode counters suggested duplicate background/demand transfers. A
wire-level regression test reproduced two downloads, 6,291,456 bytes total, for
one 3,145,728-byte output. Sharing an active read now transfers 3,145,728 bytes.
This does not change compression, action validity, server negotiation, or node
identity. The per-remote table holds at most 128 active reads, releases results
with the current readers, and wakes waiters on failure or worker panic.

The seven-phase Xcode check passed after this change: all three remote restores
hit four of four actions and matched twelve output files exactly. Cold batch
payload was 18,351,285 bytes, restarted-reader payload 452 bytes, and edited
payload 16,896,156 bytes with 1,358,308 bytes reused. This addresses duplicated
work, not stronger cross-revision similarity. See the main chunking document for
the comparison and measurement boundaries.

Next worthwhile experiments: more real object edits before adopting section
resets; native, separately negotiated Swift field/dictionary transforms; and
duplicate chunks shared by different large nodes. The last needs a dependency-
safe design so concurrent overlapping recipes cannot wait on each other.

## Native Swift patch search (second segment)

The next bounded eight-run segment measures three historical ProjectDescription
public edits plus a body-only edit. It does not mix their totals with the previous
ten-output chunking corpus. Run `./autoresearch.swift.sh`, using
`AUTORESEARCH_FIXTURES` with the same named-pair manifest shape and configuration
`autoresearch.swift.json`. The production encoder and protocol remain unchanged.

The baseline is a dictionary patch of the original output bytes. Candidates
separate container fields natively, optionally difference successive values in
each column, and vary the compression history window, strength, and column key.
All original integer values, padding, and variable-integer group counts survive.
The benchmark checks both module bytes and the complete compressed node identity,
including synthetic nonempty graph references. The parser supports only bounded
recognized bitstream containers and is not part of the shipping library.

Primary: warm_bytes, the smaller of the patch plus 192 estimated envelope bytes
and the original compressed node. Identical outputs cost zero without a patch.
Cold readers keep the original whole transfer, so cold_bytes is unchanged.
Secondary: base_prepare_ms, target_prepare_ms, patch_ms, restore_ms, verify_ms,
prepared_bytes, and peak_rss_bytes. Times are sums of per-pair three-sample medians.
Receiver cold-base cost includes base_prepare_ms as well as restore_ms and
verify_ms; do not describe inverse-transform time as total download cost.
Disk access, networking, base discovery, and authorization are not modeled.

Research guardrails for this workload: exact reconstruction, at most 512 mebibytes
process peak memory, and at most 150 milliseconds receiver work per two-megabyte
module. Any retained candidate must save bytes after the envelope estimate.
These are exploratory budgets, not service guarantees. Prepared data expands,
and caching it would require its own storage budget. Larger real-action outputs
are a separate scale check after the bounded search, not a change to its metric.
