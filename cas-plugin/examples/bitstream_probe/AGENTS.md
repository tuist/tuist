# Experimental bitstream preparation

This is an offline benchmark module, not a production decoder or negotiated
transfer format. It separates bitstream fields without changing their values,
padding, abbreviation spelling, or variable-integer group counts. Follow the
[bitcode container specification](https://llvm.org/docs/BitCodeFormat.html).

Keep explicit input, expansion, operation, abbreviation, and nesting limits.
Malformed or unsupported input must return an error. Every experiment must
reconstruct the original compiler output and its compressed node identity.
Do not connect this module to network-facing production code. Promotion needs a
separate capability, authorized digest-pinned bases, resource bounds, fuzzing,
missing-base fallback, and compiler-consumer checks.

`grouped.rs` compares stable field identities in bounded pages. Its offline
envelope pins prepared-base and prepared-target hashes and bounds decoded group
metadata, page sizes, and total output. Copy, prefix patch, literal, and bytewise
difference modes must all preserve every byte. Count the compressed metadata as
transfer bytes. Bounded page comparisons do not mean bounded total memory: the
current preparation and inverse still retain whole expanded representations.
Do not claim streaming, base discovery, authorization, or network integration.

Any future production field-patch path must remain experimental and explicitly
opt-in per project. Missing, empty, or invalid configuration means disabled;
server support alone must never enable it. The opt-in must accompany requests
and background work, not mutate a machine-wide proxy switch. Opt-in does not
bypass capability negotiation, base authorization, or resource limits. Add the
build setting only with a working supported runtime path, not as a no-op flag.
