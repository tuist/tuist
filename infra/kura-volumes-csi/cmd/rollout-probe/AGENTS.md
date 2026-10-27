# Kura rollout probe

`main.go` is a bounded HTTP probe for checking cache traffic during staged rollouts.
It seeds random 16 KiB objects, verifies the saved corpus byte-for-byte, or runs
concurrent reads/writes against an explicitly supplied URL. Tokens are read from
a file and never logged. Corpus and token files must not be committed. It has no
explicit retry loop; Go's transport can retry an idempotent request after a stale
connection. Reports count every observed failure, including failed writes.

Keep generated reports outside the source tree. Preserve failure timestamps and
distinguish migration observations from controls when recording rollout evidence.
This probe does not exercise ingress, runner demand, physical disk installation,
or full-corpus durability. Use it only against an authorized test instance.

Run `go run ./cmd/rollout-probe -help` from `infra/kura-volumes-csi` for options.
Seeding and soaking write cache objects; use a scoped token and an explicitly
authorized test instance. Verification reads the corpus created by seeding.

`soak -journal PATH` creates an exclusive bounded JSONL file containing only the
key, size and hash of each successful write (at most 20,000). After the soak,
`verify-journal -state PATH -expected-writes N` checks every acknowledged object
and rejects a truncated, oversized or incomplete journal. Set N from the soak
report's successful-write count. This complements the pre-seeded corpus check;
it does not infer durability from a successful PUT or replication cursor.
