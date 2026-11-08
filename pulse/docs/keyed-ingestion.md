# Keyed ingestion and immutable retries

Pulse accepts `Idempotency-Key` on its OTLP/HTTP, Loki push and Prometheus
remote-write receivers. The key is **content-addressed**, not an exclusive
reservation: the same key with different normalized caller content names a
different object. Use a nonempty key; missing/empty keys are unkeyed at the storage
layer. Unkeyed ingestion remains at-least-once and uses fresh names.

## Durability and retries

Keyed uploads use conditional object creation (`If-None-Match: *`). A successful
create still needs manifest conditional publication before acknowledgment. Any
instance can handle a retry; no sticky routing, owner election, database or local
retry state is required.

A failed create might have committed despite its response being lost. Pulse
therefore verifies the existing object after **any** failed keyed create, not
just a precondition response. Only an exact byte match permits registration of
the locally encoded segment's size and summaries. This also recovers a matching
unpublished upload after process loss. Manifest failures still fail the request;
a subsequent retry reuses the object and repeats conditional manifest publication.

Verification is a streaming GET against the already-encoded input. It checks
advertised size, every consumed chunk and final length, without allocating or
copying a second full object into the Erlang heap. It stops on mismatch. Each
verification has a 15-second native timeout; an explicitly supplied internal
append deadline can shorten it. This is not an end-to-end receiver deadline:
encoding, conditional PUT, manifest CAS and already-running native work retain
their own bounds. Native transport chunks, the encoded input, and aggregate
provider pressure remain outside BEAM heap guarantees.

If a precondition response is followed by a missing object, cleanup may have
raced verification. Pulse allows at most two create/verify rounds per append.
Provider client retries within each operation are additional. Other provider
conflict/error forms can instead require another client retry. A missing,
unavailable or timed-out verification never acknowledges an upload. A streamed
body that disagrees with its advertised length is a retryable transport/provider
failure, not a permanent byte-conflict diagnosis.

These recovery GETs add provider requests and body traffic on keyed retries and
failed creates. Every serving instance can generate them; node-local admission
is not a deployment-wide request budget. Self-monitoring counts GET operations
and consumed body bytes, including mismatched GETs. Header rejection can consume
no streamed body but still incur a provider GET and transport traffic; those
counters are not provider-billed wire-byte accounting.

## Permanent conflicts

Different existing bytes return **HTTP 409** with reason
`keyed_content_mismatch`, without `Retry-After`. OTLP JSON/protobuf status bodies
use code 6 (`ALREADY_EXISTS`); Loki and remote-write JSON expose the same error
reason. No new data is appended or manifest entry registered by this conflicting
request, and existing bytes are never overwritten or guessed away.

This is deliberately **exact-byte**, not semantic cross-encoder recovery. Even
two valid Parquet objects representing identical logical samples can conflict
if produced by different writer/dependency versions. A conflict can also indicate
corruption or an object-key collision. Verification does not add an independent
object checksum: same-length corruption in transit can also appear as a conflict.
Use TLS in production; plain-HTTP deployments rely on TCP checksums alone. The existing object might already be
acknowledged, might be retired into a replacement, or might be unpublished; a
409 does not establish which. It never establishes exporter completeness.

Repeatedly retrying identical conflicting bytes does not converge. Alert on
`pulse_keyed_publication_conflicts_total`, preserve evidence and inspect the
writer versions and coherent object/manifest history. Do not blindly delete or
overwrite the object, rotate the key, or resend the batch unkeyed: those actions
can lose evidence or duplicate already stored data. Recovery across genuinely
different encodings needs a compatible writer or an explicitly validated restore
or migration; automatic semantic recovery is not implemented.

A conflicting native Prometheus recording intent remains at the head of its rule's
bounded durable publication queue. Its `recording_error.reason` is
`keyed_content_mismatch`, not a transient storage diagnostic. Later results wait
behind it until compatible encodings/storage history are reconciled; the publisher
never skips or acknowledges the conflicting intent to unblock the queue.

Transient storage/recovery/publication errors retain their existing retryable
receiver responses. Do not confuse a provider's conditional-write HTTP 409 with
Pulse's application-level byte-mismatch 409: a provider conflict is verified and,
without a matching object, remains a retryable storage failure.

## Compaction, retention and orphan uploads

The existing manifest CAS, retirement records and latest event-time retention
floor remain the only visibility/deletion authority. Conditional object creation
does not bypass publication-time retention checks. A retry of a compacted source
must not re-expose it or duplicate the replacement. If cleanup already removed
the source, a retry can recreate an unreferenced copy; registration rearms its
existing retirement cleanup rather than making it queryable.

Uploads whose publication fails can remain orphaned, as before. Managed retention
sweeps reclaim only according to their committed watermarks and bounded catch-up
policy. Retain-forever flat catalogs have no general orphan-upload sweeper;
known retired sources still have durable cleanup. Never infer that an upload is
safe to delete from a failed response alone: manifest publication may itself
have succeeded ambiguously. See [retention](retention.md).

## Upgrade requirements

The provider must correctly implement conditional object creation as well as
manifest conditional writes. Providers that ignore `If-None-Match` do not meet
Pulse's correctness requirements.

**Upgrade or drain every writer before relying on immutable keyed publication**,
including ingestion nodes and alert/recording evaluators that append metrics.
Old application versions can still issue unconditional PUTs and overwrite a
new node's object. Local startup checks, a Helm Recreate strategy or routing one
request to a new node do not fence old participants in another serving pool.
New S3 applications require matching object-store native API tuple `{1,1,1,1}`
(retention, keyed publication, snapshot GET, asynchronous requests). Snapshot reads do not change
keyed encoder bytes; see [footer-first pruning](metric-footer-pruning.md) for
current metric reader requirements.

Keep byte-compatible encoders during retries. Keyed metric writes still use
the pre-postings encoder, while fresh unkeyed/compacted objects can add postings.
This prevents that footer increment from changing deterministic-key bytes; it
refers to the metadata-envelope-era encoder, **not historical six-column metric
or ten-column log encodings**. Adding nullable metadata columns can change bytes
even for plain remote-write samples or logs without an OTLP envelope, while their
deterministic key remains the same. Drain **all legacy keyed log/metric retries**
before upgrading, not only rich OTLP retries. Existing legacy objects can produce
permanent 409 conflicts with the new encoder. No semantic-equivalence rewrite,
overwrite, deletion, key change or unkeyed/subset resend is a safe automatic
repair. Preserve compatible readers and versioned backups. This also does not
promise compatibility across future Parquet/compression dependency changes. A mixed/incoherent writer rollout can cause conflicts or existing
`segment_summary_mismatch` compaction failures. Stopping old writers prevents
new damage but does not repair already inconsistent objects/manifests.

The separate all-reader/writer/compactor upgrades for rich log/metric/trace
metadata still apply. Preserve coherent versioned backups and rollback artifacts.
Conditional creation does not establish deployed-provider, separate-node,
restoration or capacity acceptance, and it is not a cutover approval.
