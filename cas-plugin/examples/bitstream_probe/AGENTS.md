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
