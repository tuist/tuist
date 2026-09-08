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

### Results, 2026-09-08

All eight configurations completed exact module and compressed-node checks.
The native implementation reproduces the earlier patch savings only when the
base is supplied as a **prefix**, not an ordinary dictionary. The upstream
[Zstandard patch implementation](https://github.com/facebook/zstd/blob/v1.5.7/programs/fileio.c)
uses prefix references and configures long-distance matching. Merely enlarging
the history window did not produce the same result. This is a useful warning
against substituting a library's default dictionary interface for its patch mode.

| Preparation and patch settings | Selected bytes across three edits | Decision |
| --- | ---: | --- |
| Original bytes, ordinary dictionary, defaults | 1,753,183 | Baseline |
| Original bytes, ordinary dictionary, 16-mebibyte window | 1,753,145 | Numerically retained, negligible difference |
| Field differences, ordinary dictionary, defaults | 1,475,149 | Keep |
| Field differences, ordinary dictionary, 16-mebibyte window | 1,484,429 | Discard |
| Field differences, dictionary, long-distance matching | 1,299,652 | Keep |
| Field differences, prefix, long-distance matching, level 1 | 504,191 | Keep |
| Original bytes, prefix, long-distance matching, level 1 | 1,307,491 | Discard against field candidate; useful lower-cost alternative |
| Field differences, prefix, long-distance matching, level 3 | 500,711 | Keep for research only |

The last four rows use a 16-mebibyte history window. The final configuration is
not automatically best for every edit: level 3 slightly improves the aggregate
over level 1, but makes the enum edit larger. No production selection policy is
being introduced from three samples.

| ProjectDescription edit | Whole compressed node | Raw prefix patch plus envelope | Native field patch plus envelope | Reduction from whole |
| --- | ---: | ---: | ---: | ---: |
| Public declaration | 588,354 | 507,419 | 200,083 | 66.0% |
| Enum change | 583,767 | 308,581 | 92,071 | 84.2% |
| Hashing change | 583,785 | 491,491 | 208,557 | 64.3% |
| Body-only change | 583,922 | 0 | 0 | Already identical, no patch needed |

The three edited originals total 1,755,906 compressed bytes; the selected field
patches plus estimated envelopes total 500,711, a 71.5% reduction. Whole sizes
include synthetic references in the node frame and therefore differ slightly
from the earlier standalone-file measurements. These are byte savings, not build
speedups, and the base must be present and authorized.

In the three-sample and confirmation runs, native preparation took 26–28 milliseconds per
module. Prefix-patch creation took 21–27 milliseconds. Patch decoding and inverse
transformation took 23–27 milliseconds, followed by about 5 milliseconds for
reconstructing and verifying the exact compressed node. A receiver preparing its
base therefore paid about 55–60 milliseconds of measured work, not the inverse
time alone. A prepared-base cache could avoid about 26 milliseconds, but each
two-megabyte module expands to about 12.3 megabytes of prepared data. The combined
in-process benchmark peaked at 179 million bytes, or 191 million in the export
confirmation run. This is not an isolated receiver-memory measurement.

Exported native reconstructions of all three modules passed a fresh-cache Swift
consumer import and type-check. The body-only module was byte-identical before
any transformation. Confirmation preserved the exact patch sizes. Tests exercise
padding, variable-integer spelling, malformed mutations, truncation, output size,
trailing data, and missing child end markers. These focused checks are not a
fuzzing campaign or validation of a remotely exposed codec.

### Scale check and next design

The same configuration also reconstructed the actual 4,000-struct Xcode module
and the exploratory Foundation precompiled header byte-for-byte, including their
compressed node identities. A Swift consumer of the restored large module and an
Objective-C consumer of the restored header both type-checked.

| Output | Whole compressed node | Patch plus estimated envelope | Prepared output | Fresh-base receiver work |
| --- | ---: | ---: | ---: | ---: |
| Xcode Swift module | 6,177,960 | 3,198,463 | 183,174,600 | 756 milliseconds |
| Foundation header | 9,130,230 | 6,495,827 | 89,710,267 | 492 milliseconds |

The combined scale-check process peaked at **1,701,347,328 bytes**, beyond the
research memory budget. Do not promote this all-in-memory representation. The
confirmation run preserved both payload sizes and peaked at 1,714,536,448 bytes.
These are whole-process pipeline measurements, not isolated decoder peaks. The
fixed 16-mebibyte matching window also cannot cover these expanded bases. The
header's result is consequently not equivalent to the earlier command-line
patch experiment, which selected its window from the expanded file size.

The next candidate should prepare and patch **one field group at a time**:

1. Give groups stable identities derived from container block, record, and
   operand, keeping spelling/layout and raw byte payloads separate.
2. Spool bounded groups or read them from mapped files; release each base/target
   pair after its patch is produced instead of holding two expanded files.
3. Use a bounded history per group. Measure the extra per-group metadata and
   lost cross-group matches, not just peak memory.
4. Reassemble every original bit and graph reference, reproduce the writer's
   pinned compression version/parameters, and verify its expected blob digest.
5. Negotiate a separate codec, authorize and pin base identities, disallow patch
   chains, and fall back to the original blob on unavailable bases or limits.

This segment is complete. Larger history windows, group-wise streaming, stronger
compression, more edits, and prepared-base caching are future experiments, not
shipping behavior. No production source or server protocol changed in this pass.

## Bounded-group patch search (third segment)

Continue on the same branch with a bounded six-run segment. The workload now
combines the three historical edits, the identical body-only pair, the large
Xcode Swift module, and the Foundation header. Establish a fresh aggregate
baseline; do not compare its sum with the small-module-only second segment.
Primary remains warm_bytes, including serialized group metadata and the outer
192-byte envelope estimate. Track preparation, patching, inverse, verification,
expanded bytes, and whole-process peak memory separately.

Hypothesis: groups keyed by container block, record, and operand keep related
bytes inside a bounded prefix window. Unchanged groups can reference the pinned
base without a patch. Fixed-size pages bound each group comparison, but may lose
matches across page boundaries. First measure byte savings with borrowed views
of the existing prepared format; this does not implement streaming preparation.
Then measure memory improvements explicitly instead of inferring them from group
size. Retain exact module and compressed-node identity checks, resource limits,
malformed-input tests, and fresh compiler-consumer checks. Production negotiation,
authorization, action validity, and transfer encodings are out of scope.

To repeat with available artifact pairs, run `./autoresearch.swift.sh` with a
manifest containing the three edits and a body-only pair. Set
`SWIFT_PATCH_RESTORED_DIR` to an existing empty temporary directory to export
verified modules/headers; existing files are never overwritten. For a Swift
consumer, place each exported file under its original module name and run
`xcrun swiftc -typecheck -target arm64-apple-macosx15.0 -I <module-directory>
-module-cache-path <fresh-cache-directory> <consumer.swift>`. The header check
used `xcrun clang -x objective-c -fno-modules -isysroot <macOS-sdk-path>
-include-pch <restored-header.pch> -fsyntax-only <consumer.m>`.
