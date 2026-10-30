# Gradle certificate-trust fixtures

These public certificates and the twelve-key `emudhra-2026-10-19-v2` policy are
extracted from [tuist/tuist#14511](https://github.com/tuist/tuist/pull/14511), pinned
at [`e2efb26eb30c0c7657601c62dd9270551f94f090`](https://github.com/tuist/tuist/commit/e2efb26eb30c0c7657601c62dd9270551f94f090).
The plugin embeds its own policy and tests; neither building nor distributing it
depends on that branch's root-level policy infrastructure.

Policy provenance:

- <https://emudhra.we-have-a-problem.com/roots.json>
- <https://emudhra.we-have-a-problem.com/intermediates.json>
- <https://github.com/golang/go/compare/go1.26.9...go1.26.10>
- <https://github.com/rustls/webpki/releases/tag/v%2F0.103.16>

`issuer-roots.pem` and `distrusted-intermediates.pem` contain the four root and
eight intermediate keys. `positive-isrg-root-x1.pem` and `positive-isrg-r11.pem`
are unrelated Let's Encrypt controls. Tests hash DER SubjectPublicKeyInfo, not
whole certificates. Offline intermediate path validation uses a date within each
fixture's validity period; it does not assert current public trust.

## Constructed paths and trust preservation

Both OkHttp (including derived Retrofit/latency clients) and HTTPS URL connections
use `CertificateTrust`. The original JVM trust manager runs first, with its
socket/engine context, constraints and revocation policy. JVM-configured enterprise
anchors remain available. Hostname verification is not replaced, and rejection
does not fall back to another transport.

A second PKIX validator uses the original accepted issuers minus blocked keys,
with a path checker for intermediates constructed by the provider. Filtering
anchors alone misses intermediate keys; checking only peer-supplied certificates
misses omitted roots and provider-fetched intermediates. The additional validator
does not enable revocation network I/O. It may reject provider-specific trust that
cannot also be represented as PKIX with exported accepted issuers; it must not
silently accept via the original verifier when the restricted check fails.

The local wire tests generate an otherwise-valid private root/intermediate/leaf
chain, serving only leaf and intermediate. They establish acceptance, add one
synthetic deny (without removing production denies), assert handshake rejection
before any HTTP delivery, and restore acceptance. Root cases cover both another
permitted anchor remaining and no permitted anchors. These controls run against
OkHttp, its derived latency client, and HTTPS URL connections. Real incident DER
checks pin all twelve keys independently of these synthetic controls.

Run from `gradle/` with `./gradlew test --no-build-cache --no-watch-fs`.
The optional public-host test is enabled with
`JAVA_TOOL_OPTIONS=-Dtuist.trust.live=true ./gradlew test --tests '*CertificateTrustLiveTest' --no-build-cache --no-watch-fs --rerun-tasks`.
Public hosts can already fail native trust; their rejection alone does not prove
that the additional restriction executed. Supported JVM/provider/OS combinations
and the final shaded release artifact need their own qualification. Installing a
source change does not update an existing plugin or restart a Gradle daemon.
