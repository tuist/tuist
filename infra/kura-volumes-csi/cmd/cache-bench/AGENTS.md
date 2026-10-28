# Bounded cache storage comparison

`main.go` compares an explicitly selected, isolated Kura fixture with its real
account-scoped token. It writes random objects, verifies returned bytes, and
records per-phase failures, throughput and p50/p95/p99 latency. It performs
400 small 16 KiB writes/reads, 64 large 4 MiB writes/reads, 24 batches of
64 large writes to exercise segment eviction, then reads the last batch.
Eight requests run concurrently. Object generation is outside timed phases;
GETs include warm-cache reads and are not a cold-disk benchmark.

Use only an authorized disposable instance. The run writes more than 6 GiB;
it is not a read-only probe. Credentials and result files stay outside git.
No request retries are added. Any failed status or checksum ends the run and
preserves the partial report. A failed run is not qualification evidence.

Keep runtime image, resource limits, host, virtual device size and client
constant; alternate layout order and report ranges rather than claiming a
precise production regression from a short sample. Include CPU throttling,
working-set constraints, failure counts and filesystem free-space margins.
The current runtime has a minimum segment ring: setting a small CAS budget
does not guarantee a small working set. Use correctly sized fixtures.

Run `go test ./...` and `go vet ./...` from the CSI module after edits. Do not
run the load against production or use global cache-dropping on shared hosts.

`-working-set` seeds 1 GiB in four bounded batches, retains only object hashes
and sizes in the client, then reads all objects in shuffled order with checksum
verification. Use a runtime memory limit below that corpus size. This exercises
a working set larger than memory without global cache-dropping, but is not proof
that every read is cold. Keep the same mode and client limits on both layouts.

With `-working-set -corpus PATH`, persist only hashes and sizes for later
`-verify-corpus -corpus PATH` checksum reads through a Service or each replica.
Verification performs no writes and accepts at most the bounded 256-object corpus.
