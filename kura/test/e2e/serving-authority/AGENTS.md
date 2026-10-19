# Serving-authority qualification fixtures

These fixtures exercise real Kura runtimes. `client.mjs` operates only on an
explicitly selected isolated Kubernetes instance and uses the real controller.
Its fencing tests keep the original HTTP/2 and gRPC sessions: do not reconnect
those channels to turn a stale-channel failure into a pass.
`api-partition.yaml` is the matching opt-in network-policy fixture. It belongs
only in the explicitly isolated test namespace, and affects only pods with the
test's fault label. Keep its namespace aligned with `KURA_SPEC98_NAMESPACE`.

`corpus.mjs` verifies action-cache output digests and every referenced CAS body.
Only idempotent verification reads may reconnect after graceful connection aging
or a bounded transport reset. A gRPC failure remains a failure. Large corpora
should be read by a bounded client pod through the actual cluster Service rather
than through a slow local port-forward.

`fixture.mjs` and `fixture-api.mjs` create disposable local Docker peers and a
TLS ConfigMap simulator for resource, disk-pressure, and complete-process-pause
tests. Their grants are test inputs, not a controller implementation. Never point
this simulator at Kubernetes, edit a real serving ConfigMap to emulate it, or
claim that Docker pause proves physical host power-off. The tmpfs pressure volume
is bounded; never fill the host disk to manufacture ENOSPC.

Run resource comparisons sequentially with the same architecture, host, limits,
load, warmup, and cooldown. Keep workload counts, metric samples, both peers' CPU,
disk, client/peer egress, memory peaks and settled levels. Preserve failures and
measurement noise in the PR evidence. Do not run another local build or load test
during a measured comparison.

`serving_authority_resource_spec.sh` opts into the pause and pressure cases with
`KURA_E2E_AUTHORITY_RESOURCES=1`, `KURA_E2E_AUTHORITY_IMAGE`, and an absolute
`KURA_E2E_AUTHORITY_OUTPUT` directory. `mesh-resource.mjs IMAGE legacy|active DIR`
compares sustained replication and verifies the retained corpus after handover.
`inline-handover.mjs IMAGE DIR` lowers the fixture's batch threshold to exercise
individual inline fetches and checks the full retained barrier. Its optional
`KURA_E2E_INLINE_RECORDS` and `KURA_E2E_INLINE_INTERVAL_MS` extend the same workload
for sequential resource comparisons; failed runs retain measurements and logs.
`KURA_E2E_AUTHORITY_STANDBY_IMAGE` exercises adjacent-version batch negotiation.
`segmented-handover.mjs IMAGE DIR` writes a paced 1 GiB segmented corpus,
verifies every body after handover, and captures the same four resource axes.
Run baseline and candidate sequentially, including its settled cooldown.
Set `KURA_E2E_SEGMENT_RECORDS=2048` for a 4 GiB full-ring qualification.
That mode captures the entire retained source subset while both holds are active
and checks its count against the matching fully verified receipts, then reads
the newest retained body after promotion. Reads on a full
serving ring can trigger eviction, so walking it after promotion is not a frozen
corpus check. It does not require evicted uploads to survive.
Add `KURA_E2E_RETAINED_RECENCY=1` to that full-ring workload to inject an old
segmented record into the source through the peer protocol. Assert that ordinary
replication leaves it absent on the full standby before requesting handover,
then require matching full-corpus receipts and byte-exact reads of the repaired
record after promotion. This isolates recency selection from storage admission;
it must not change either replica's configured capacity to make repair pass.
Add `KURA_E2E_LIVE_PREPARATION=1` to exercise the preceding Serving-phase
preparation with a capable destination. Require primary writes to succeed and
standby writes to fail while no receipts exist, then use the unchanged bounded
Quiescing barrier. The 20-minute preparation deadline is separate from its
five-minute cutover deadline. Preparation completion never replaces frozen-corpus
verification. Long preparation runs must establish and successfully exercise their
stale-channel test sessions while still Serving immediately before Quiescing;
keep those exact sessions through the transition and preserve aging failures.
Add `KURA_E2E_LIVE_WRITE_CHURN=1` to the full-ring preparation workload to keep
rewriting 2 MiB records until Quiescing rejects writes. Preserve the same source
keys and bytes so the held-corpus check still verifies every retained body. A
preparation success must not replace the final repair, hold or matching receipt.
`KURA_E2E_PREPARATION_DEADLINE_MS` may shorten only this simulator phase for a
bounded failure comparison; the default remains 20 minutes and the final barrier
remains five minutes. Record any shortened deadline with the measurements.
Alternatively set `KURA_E2E_REPAIR_CHURN=1` on the full-ring workload to add 1 GiB
of old destination-only data. Assert it stays absent on the source, then require
an eviction-triggered repair revisit and matching full-corpus receipts before
promotion. Both peers retain the same 3 GiB ring budgets. This complements the
Rust regression that removes an already-checked blob and its action-cache entry
through the real eviction path while a later missing body is being fetched.
`resume.mjs` interrupts the local authority API, holds an admitted upload across
expiry and supplies explicit fencing/resumption grants; it verifies drained
publication, recovery when a replacement grant arrives after expiry, retained
reads, persistent-channel writes and dirty-restart refusal.
It is still a simulator. `client.mjs api-recovery` exercises the real controller
with the isolated pod's API-partition policy, requiring the same incarnation,
one new epoch and absence of the rejected upload after API access returns.
Run-specific manifests, keys, logs and results belong in a temporary output
directory, never in the repository. Remove only resources created by the fixture.

The pressure case restores free space and repeats handover on the same standby
incarnation. Preserve this no-restart check: restarting could mask missing
retained records behind a new bootstrap rather than testing named repair.
Its source has a 3 GiB ring and the destination a 4 GiB ring in a bounded 6 GiB
tmpfs, initially pressured with a 2.25 GiB filler. Restoring free bytes alone
does not guarantee that equal-sized fragmented rings can converge; the extra
destination capacity makes the successful recovery case explicit without
bypassing ring capacity or quota-aware disk admission.
Capture the expected pressure corpus only after both receipts exist, while the
source hold prevents read-time promotion and eviction. A pre-hold walk of a full
ring can evict records it counted earlier and is not the retained barrier.
