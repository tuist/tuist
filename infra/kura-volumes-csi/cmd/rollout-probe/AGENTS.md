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
