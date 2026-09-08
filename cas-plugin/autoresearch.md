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

### Results, 2026-09-08

The six-run segment is complete. An initial one-mebibyte grouped probe preceded
the logged confirmation. The grouped codec is confined to the offline example.
There are no production client, server, or compiler-setting changes in this pass.

| Candidate | Selected bytes | Decision |
| --- | ---: | --- |
| Previous monolithic prefix patch, expanded corpus | 10,195,001 | Baseline |
| Four-mebibyte pages, prefix patches | 2,205,669 | Discard against preliminary one-mebibyte probe |
| One-mebibyte pages, prefix patches | 1,783,604 | Confirmed research candidate |
| Also allow bytewise differences | 1,538,335 | Keep for research |
| Also compress group descriptors separately | 1,324,969 | Keep for research |
| Reduce pages to 256 kibibytes | 1,243,833 | Keep for research |

The initial one-mebibyte probe also selected exactly 1,783,604 bytes. Between
that probe and its logged confirmation, preparation/output buffers were
preallocated and the target prepared buffer was released before reconstruction.
These changes preserved bytes, but did not materially improve process memory.
The helper initially declined the log because group counters were new secondary
metrics; the later confirmation supplies the durable entry. No failed correctness
run was retained. An early mutation test was corrected to allow harmless changes
to unused metadata only when the accepted output still equals the exact target.

| Output | Whole compressed node | Previous monolithic patch | Final grouped patch | Reduction from whole |
| --- | ---: | ---: | ---: | ---: |
| ProjectDescription public declaration | 588,354 | 200,083 | 158,211 | 73.1% |
| ProjectDescription enum change | 583,767 | 92,071 | 50,307 | 91.4% |
| ProjectDescription hashing change | 583,785 | 208,557 | 169,102 | 71.0% |
| Foundation precompiled header | 9,130,230 | 6,495,827 | 776,089 | 91.5% |
| Actual 4,000-struct Xcode Swift module | 6,177,960 | 3,198,463 | 90,124 | 98.5% |

Patch columns include actual serialized metadata and 192 estimated outer-envelope
bytes. The changed whole outputs total 17,064,096 bytes. Grouped patches total
1,243,833, a 92.7% reduction from whole and 87.8% below the previous monolithic
patches on this same corpus. The body-only pair was already identical and costs
zero without any patch; its 583,922-byte whole size is included in cold_bytes
but excluded from these changed-output totals. The three small modules improve
from 500,711 to 377,620 bytes. These selected local pairs are not a customer
distribution, and the generated module's single-property rename is especially
favorable once field groups isolate the change.

### Why the groups help

The [bitcode container](https://llvm.org/docs/BitCodeFormat.html) exposes block,
record, and operand boundaries. We preserve their original values and spelling,
then compare the same field kind between revisions. These are container identities,
not stable declaration identities, and no Swift reference is renumbered. Layout,
raw byte payloads, and individual numeric columns have separate group identities.
Large groups are split into fixed-size pages. A page chooses an exact base copy,
a bounded prefix patch, a literal, or compressed bytewise differences.

The [Zstandard window documentation](https://github.com/facebook/zstd/blob/v1.5.7/programs/zstd.1.md)
explains why a bounded comparison can help: the monolithic prepared files exceed
the old matching window. Grouping brings the corresponding base page back into
reach. Fixed pages still lose some matches around insertions; they are not a
semantic equivalence algorithm or a replacement for content-defined boundaries.

Bytewise subtraction follows the observation in
[Colin Percival's binary-patching paper](https://www.daemonology.net/papers/bsdiff.pdf)
that changed references can have sparse, repetitive differences without long
exact matches. This experiment does not implement that paper's suffix matching:
it only tries aligned equal-size pages and keeps a difference when it beats the
prefix patch or literal. Wrapping byte arithmetic is exactly inverted.

Repeated group descriptors were another avoidable cost. Compressing that index
separately dropped metadata from 237,544 to 24,178 bytes at one-mebibyte pages.
The final smaller-page candidate has 8,912 groups and 25,990 metadata bytes.
Its exact-copy mode reuses 213,065,780 **prepared** bytes; that figure must not be
reported as downloaded bytes saved because preparation expands the output.

### Costs, correctness, and next work

Confirmation reproduced all patch sizes. Fresh-base receiver work, including
preparation, patch verification/decoding, inverse transformation, and compressed
node verification, was about 116–117 milliseconds for each small module,
908 milliseconds for the header, and 1,617 milliseconds for the large Swift
module. This is more processing than monolithic patches. Disk, network, base
discovery, authorization, and prepared-base persistence remain unmeasured.

Process peak memory was 1,821,573,120 bytes in the final search run and
1,810,710,528 in confirmation. A live `vmmap -summary` diagnostic during the
previous candidate showed about 453 mebibytes allocated, plus 783 mebibytes of
resident empty large-allocation regions and 126 mebibytes of resident empty small
regions. This snapshot is evidence of allocator retention, not an isolated
decoder peak or a memory fix. The bounded page size does not bound the current
whole prepared files, and the candidate still fails the 512-mebibyte promotion
budget. It is retained only as offline evidence for a better transfer format.

All five changed outputs reconstructed exactly, including compressed-node bytes
and digest with nonempty synthetic references. Exported results passed four
fresh-cache Swift consumer type-checks and the Objective-C header consumer check.
The example now has eight focused tests, covering the original parser plus new
groups, exact copies, changed pages, modular byte differences, incorrect bases,
truncation, mutations, trailing bytes, duplicate groups, and envelope bounds.
The three chunk-boundary tests, three chunking-example tests, 109 library tests,
and ten negotiation/backpressure tests also passed. Two live-Kura chunk tests
were explicitly ignored in this pass because no local Kura was running. This is
not a new end-to-end network test of grouped patches, which have no network path.

### Rollout decision: explicit opt-in, never the default

The experimental field-patch format must not become the default transfer path.
Server support is necessary but is not consent to enable it. Missing, empty, or
invalid project configuration must leave it off. Ordinary negotiated chunking
and local chunk reuse are separate features and keep their existing behavior.

The proposed Swift-only setting is
`TUIST_XCODE_CACHE_EXPERIMENTAL_FIELD_PATCHES`, defaulting to `NO`. When a supported
runtime path exists, generation can expand that value into the `tuist-field-patches`
plugin option through `OTHER_SWIFT_FLAGS`. This setting is not implemented today:
the codec remains an offline example. Arbitrary build settings should not be
assumed to appear in the compiler plugin's environment.

An explicit opt-in must travel with each transfer request and queued publication,
including background materialization. It must not toggle the shared proxy for
other projects or silently opt in another build configuration. Supporting Clang
outputs needs a separate project-scoped configuration path because the current
Swift compiler flags do not reach Xcode's build-system-managed Clang cache.

Before activation, require compatible plugin/proxy/server support, an authorized
digest-pinned base, and available memory/processing budgets. Unsupported versions,
unavailable bases, or exceeded limits must retain ordinary transfers. Old clients
must remain able to retrieve the original output. Test disabled and mixed-version
paths as well as opt-in, proxy restarts, queued work, and concurrent projects with
different settings. An experimental opt-in does not waive the promotion work below.

Next work, before considering a production codec:

1. Prepare compact or spooled field streams and reuse bounded scratch buffers.
   Measure live allocations, retained memory, and receiver-only peak separately.
   An isolated worker could also contain parser failure and allocator retention,
   but its overhead and peak must be measured rather than assumed away.
2. Profile hashing separately. Source inspection found that our current
   [hash implementation selects software on Apple silicon unless its assembly
   feature is enabled](https://github.com/RustCrypto/hashes/blob/sha2-v0.10.9/sha2/src/sha256.rs).
   The [accelerated backend checks processor support at runtime](https://github.com/RustCrypto/hashes/blob/sha2-v0.10.9/sha2/src/sha256/aarch64.rs).
   Benchmark an accelerated build and verify both supported architectures before
   changing a shipping dependency. No acceleration is enabled by this experiment.
3. Test insertion/deletion, multiple edits, different build modes, toolchain
   revisions, and unrelated bases. A transfer selection policy must include
   processing cost and fallback, not choose solely from patch size.
4. Keep base authorization, digest-pinned identities, missing-base fallback,
   chain prevention, concurrency limits, and separate capability negotiation as
   required production work. The offline envelope validates the prepared base,
   but does not perform remote authorization or discover a suitable local base.

This optimizes transfer reuse, not compiler invalidation. A changed action must
still have been compiled somewhere before its exact output can be reconstructed.

To repeat with available artifact pairs, run `./autoresearch.swift.sh` with a
manifest containing the three edits, the body-only pair, the large Xcode module,
and the Foundation header. Use the checked-in grouped configuration, or set
`group_bytes` to zero and `residual` to false for the monolithic baseline. The
historical temporary artifacts are not bundled; regenerated artifacts establish
a new corpus rather than reproducing these exact byte counts. Set
`SWIFT_PATCH_RESTORED_DIR` to an existing empty temporary directory to export
verified modules/headers; existing files are never overwritten. For a Swift
consumer, place each exported file under its original module name and run
`xcrun swiftc -typecheck -target arm64-apple-macosx15.0 -I <module-directory>
-module-cache-path <fresh-cache-directory> <consumer.swift>`. The header check
used `xcrun clang -x objective-c -fno-modules -isysroot <macOS-sdk-path>
-include-pch <restored-header.pch> -fsyntax-only <consumer.m>`.

## Receiver-cost search (fourth segment)

Keep the six-pair grouped workload and start a bounded six-run segment with
receiver_ms as the primary metric: the sum of base preparation, patch decoding
and inverse transformation, and compressed-node verification. Each phase remains
a three-sample median per pair. Secondary metrics include transferred bytes,
sender work, expanded size, and peak process memory. This is a change of metric,
not a new corpus. Remain on the existing pull request branch.

First isolate verification cost with the same digest algorithm and patch bytes.
Then try compact spelling/layout streams and variable-length numeric columns.
Preserve every compiler-visible bit and compressed-node identity. Reject an
aggregate warm-byte regression over 10% or any individual regression over 25%
from the preceding grouped candidate, even if receiver work improves. Memory
must not materially exceed the baseline; the 512-mebibyte promotion limit still
applies, and retained offline candidates exceeding it are not shipping candidates.

Only examples, development-only dependencies, and research notes are in scope.
Production hashing, server protocols, default behavior, and the unimplemented
project opt-in setting are not changed. Run compiler-consumer checks on retained
reconstructions and record the actual costs, not a predicted download speedup.
