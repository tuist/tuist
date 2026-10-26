# Encrypted LVM rehearsal evidence

`probe.go` is the bounded staging HTTP probe used by the adjacent rollout report.
It seeds random 16 KiB objects, verifies the saved corpus byte-for-byte, or runs
concurrent reads/writes against an explicitly supplied URL. Tokens are read from
a file and never logged. Corpus and token files must not be committed. It has no
explicit retry loop; Go's transport can retry an idempotent request after a stale
connection. Reports count every observed failure, including failed writes.

Dated directories contain sanitized result JSON, not credentials or payloads.
Preserve failure timestamps and distinguish migration observations from controls.
This probe does not exercise ingress, runner demand, physical disk installation,
or full-corpus durability. Use it only against an authorized test instance.
