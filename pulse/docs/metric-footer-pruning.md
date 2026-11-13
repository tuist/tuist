# Optional metric footer-first pruning

Pulse can read a bounded Parquet footer before downloading a metric segment.
When its time statistics and complete label postings prove that **no row group
can match**, the full-object GET is avoided. This is an optional read
optimization, not an external index, selected-column/page range reader, or a
larger supported query capacity.

## Enable

Default: disabled. Set `PULSE_METRICS_FOOTER_PRUNING_ENABLED=true`, or with Helm:

```yaml
metricsFooterPruning:
  enabled: true
```

It applies to ordinary S3 metric queries, including raw MCP metrics and PromQL
reads used by HTTP, MCP and native alert evaluation. Metric label/series discovery
still uses whole-object scans. Logs, traces, ingestion, compaction and retention
publication are unchanged. Disable the option to restore the ordinary read path;
no file or manifest migration is necessary.

## Provider prerequisites

The S3-compatible endpoint must honor suffix `Range` requests, supply **strong
ETags**, and support `If-Match` on GET. Test against your actual provider before
enabling. A malformed/ignored range, weak/missing ETag, changed ETag or size,
partial body, provider error or deadline fails the whole query. Such transport
failures do **not** become empty results or silently switch to an unconditioned
read. An ETag mismatch is retryable storage failure, not an ingest byte conflict.
Use TLS outside a trusted local network. Provider ETags and footer checksums are
not cryptographic end-to-end authentication or independent integrity proofs.

Every serving application/native pair must have matching artifacts: metric codec
API `{2,2,1,1,1,1}` (metadata/start timestamps, OTLP, postings, discovery, footer planning, streaming reads), object-store
API `{1,1,1,1}` (retention, keyed publication, snapshot GET, asynchronous requests). Startup checks cannot
fence old pooled applications. There is no new segment format or change to
keyed encoder bytes. Existing rich-metadata and immutable-keyed-publication
all-participant upgrade/drain requirements still apply independently.

## Compact optional postings

New indexed segments (fresh unkeyed writes and compaction outputs) can store
large postings in an `s1:` envelope: hex-encoded raw Snappy around the existing
checksummed postings binary. Parquet column compression does not compress this
footer metadata. Indexes below 1 KiB decoded remain plain hex; larger indexes
use the envelope only when its complete text is smaller. No setting is needed.

Readers retain the 64 KiB text and 32 KiB decoded-index limits, inspecting the
Snappy declared size before allocating decoded bytes. Both encodings undergo
the same checksum, complete-partition and actual row-group coverage checks.
Truncated/corrupt/unknown envelopes or over-budget decoded sizes make the index
unknown, never proof of an empty result. Existing plain-hex indexes and historical
namespace aliases remain readable. Older readers reject the non-hex envelope
and scan rather than falsely exclude; upgrade app/native pairs to gain pruning.

This reduces newly written object/footer bytes without changing columns,
keyed encoder bytes, native ABI, publication or scan charging. Existing objects
are not rewritten merely to adopt compression. Benefit depends on index size
and compressibility; writing/parsing adds bounded CPU and temporary buffers.
It is not a row-group range-read implementation or a production-capacity claim.

## Read and cost contract

1. Fetch at most the last 64 KiB, capturing the full size and ETag.
2. If needed, fetch a larger suffix once, at most 1 MiB, under that ETag.
3. Inspect the same row-group time/statistics and optional complete postings
   used by the full decoder. If no row group survives, return no samples for
   that source. Otherwise, GET the complete object with `If-Match`.

An already-complete suffix is reused without another body GET. Missing,
unrecognized, damaged or over-budget optional index/footer evidence cannot
prove absence: it requires the complete matching snapshot and normal decoding.
A corrupt full file still fails. There are at most two suffix probes plus one
full-object request per source attempt, excluding native SDK retries. A 404 after
a probe retains reserved scan costs when the manifest scan retries; a 412 fails
rather than combining an old footer with a new body.

**There is a tradeoff:** proven-empty large sources save body bytes. Sources
that still match can cost one or two additional GETs and duplicate footer
traffic. Index-free or high-cardinality sources often cannot be excluded by
label matchers. A single matching row group still needs a whole-object GET.
Every instance adds independent provider pressure. Measure query mix, GET count,
bytes, latency, rejection rate and node memory; this is not deployed-provider,
representative cold-history or multi-instance capacity evidence.

## Bounds and completeness

- Existing whole-query object/byte/row admission stays in place. Each visited
  source is charged the **greater of its full logical size and total transferred
  successful body bytes**, even when only its footer was downloaded. Small full
  suffixes cost their size once. Extra full-body/probe traffic can make queries
  hit limits sooner; successful body bytes are not provider-billed wire bytes.
- The enabled path additionally caps **each source at 128 MiB and one million
  actual footer rows**, even if a direct internal caller supplies no scan limits
  or larger limits. Smaller remaining query budgets take precedence.
- Actual footer/group row counts must agree and are charged before expansion or
  exclusion. Undercounted manifest rows cannot hide scan work.
- Each snapshot GET has a native timeout of at most 15 seconds, shortened by the
  query deadline. Checks between stages stop further work, but already-running
  native metadata parsing is not preempted by that deadline.
- The 1 MiB footer bound limits optional input, not Arrow/parser/container memory.
  Native scratch is outside the BEAM task heap bound; this is not node-wide or
  deployment-wide memory admission.
- Exclusion is **not an integrity scrub**. Data columns in excluded sources are
  not downloaded or validated. As with existing Parquet statistics/postings,
  semantic coverage trusts the first-party writer; malformed optional evidence
  adds reads, never false-negative pruning.

Results preserve the normal filters, timestamps, typed metadata, stale/non-finite
values and completeness/error policy. No truncation, sampled dictionaries, new
mutable authority or altered retention floor is introduced. External indexes,
selected-row-group/column range reads, and workload/provider acceptance remain
follow-ups. See [metrics](metrics.md), [metric discovery](metric-discovery.md) and
[storage costs](storage-costs.md).
