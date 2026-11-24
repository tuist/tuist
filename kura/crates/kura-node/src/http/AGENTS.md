# HTTP implementation helpers

The main HTTP router and shared admission, authorization, serving, and usage
helpers remain in `../http.rs`. `upload_tests.rs` covers typed incoming-body
failures, checksum validation, and cleanup.

Tuist Cargo compilation caching uses the existing project-scoped Bazel Remote
Execution API in `../reapi/`, not a custom HTTP protocol. The Swift client owns
compilation eligibility and action identities; the server remains an ordinary
SHA-256 REAPI CAS and Action Cache.

- Hash checksum-declaring HTTP uploads while staging, verify size/hash before
  persistence, and retain request-owned cleanup and memory/disk admission.
- Use existing namespace authorization and write policy. Do not introduce an
  alternate caller-supplied project selector alongside the existing target.
- Do not add client-specific CAS formats, metadata compare-and-swap or compiler
  promises to HTTP in order to emulate features absent from standard REAPI.
- New server behavior requires resource qualification on all four axes; client
  cache hits alone are not a server resource qualification test.
