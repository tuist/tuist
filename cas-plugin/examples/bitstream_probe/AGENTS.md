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
preparation still retains all field buffers. `segments.rs` can avoid flattening
those buffers and borrow unchanged target pages from the verified base. Preserve
hash verification across the logical byte sequence and check reads spanning
segment boundaries. This is copy avoidance, not streaming or constant memory.
Do not claim base discovery, authorization, or network integration.

The compact offline representation records repeated operation layouts as runs
and numeric columns as variable-length integers, optionally encoding signed
differences. These are reversible storage encodings, not compiler normalization.
Preserve original padding and variable-integer spelling separately. Keep the
legacy research representation readable, reject unknown flags and noncanonical
compact integers, and bound sparse column slots as well as descriptor counts.
The optional accelerated hash must produce identical digests and patch bytes;
cross-check both implementations. Its dependency is development-only and must
not change production hashing or capability negotiation.

Any future production field-patch path must remain experimental and explicitly
opt-in per project. Missing, empty, or invalid configuration means disabled;
server support alone must never enable it. The opt-in must accompany requests
and background work, not mutate a machine-wide proxy switch. Opt-in does not
bypass capability negotiation, base authorization, or resource limits. Add the
build setting only with a working supported runtime path, not as a no-op flag.
