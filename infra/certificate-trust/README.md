# eMudhra certificate policy and offline qualification

This is the shared policy foundation extracted from [PR #14511](https://github.com/tuist/tuist/pull/14511).
It adds public evidence and an offline verifier probe, not a rollout or a change
to any production application's certificate validation.

## Policy and evidence

`policy.json` records twelve SHA-256 fingerprints of complete DER-encoded
SubjectPublicKeyInfo values, with the exact DER encoded as base64: four root
keys and eight intermediate keys. Match keys, not certificate names or whole
certificate fingerprints; a cross-sign can reuse the same public key.

The policy's `sources` field identifies the public incident root/intermediate
inventories, the Go 1.26.10 change and Rust WebPKI release. The checked-in
`controls/issuer-roots.pem` and `controls/distrusted-intermediates.pem` are
public certificate evidence for those four and eight keys respectively.
`controls/positive-isrg-root-x1.pem` and `controls/positive-isrg-r11.pem`
provide an unrelated signed chain. Tests verify every policy DER/hash against
exactly one negative certificate, the four/eight split, CA roles and signatures.
No compromised private keys are needed or included.

`controls/tls-leaves.pem` adds six public server leaf certificates issued by the
six incident TLS intermediates. `controls/tls-leaves.json` records their source
hostnames, collection time, certificate hashes and immediate issuer-key hashes.
They were collected once from public TLS handshakes with ordinary OpenSSL
verification enabled, without HTTP requests or credentials. The collection's
success is not evidence of protection; these hosts serve incident chains.
The checked-in leaves let the offline probe exercise an incident intermediate
below a real server leaf, with hostname and server-authentication checks.

These fixtures are local inputs: tests and the probe do not download inventory,
contact incident hosts, read system trust or authenticate to any service.

## Qualify the Go verifier

Run from the repository root with a genuine Go 1.26.10 compiler on PATH:

```sh
unset GOROOT
export GOWORK=off GOTOOLCHAIN=local TRUST_EXPECTED_GO_SDK=go1.26.10
go -C infra/certificate-trust test -count=1 ./...
go -C infra/certificate-trust vet ./...
go -C infra/certificate-trust run .
```

The separate standard-library-only module is deliberately not in `go.work`.
`GOTOOLCHAIN=local` prevents automatic compiler selection from substituting for
the SDK being evaluated. The expected version check also catches accidentally
running the probe with a different compiler. The GitHub workflow selects this
module's version, has contents-read permission only and persists no checkout
credentials. It installs the toolchain, then performs the qualification offline
by construction: only the standard library and embedded fixtures are used.
`TRUST_EXPECTED_GO_SDK` is mandatory for both tests and the executable; an unset
or mismatched compiler selection fails rather than silently qualifying PATH.

The probe restores incident issuers as explicit trust anchors, checks signatures
and shared validity windows, then requires the qualified Go verifier's specific
rejection. It checks all eight intermediate certificates directly and also
verifies each of the six public TLS leaves with its incident issuer in
`Intermediates`, a separate root, a matching hostname and server-auth usage.
A leaf-only deny cannot pass those six full-chain controls. The unrelated ISRG
intermediate must also verify. Missing roots, invalid signatures, expired
certificates or fixture parse failures must not masquerade as negative controls.

Go 1.26.10's source maps the distrust filter to `CertificateInvalidError` with
`NoValidChains` and empty `Detail`; other relevant native failures have different
classifications. Re-check that mapping in the source of every proposed SDK.
An identical error shape alone is not timeless proof of a particular filter.

Go 1.26.10 passes eight direct intermediate controls and six TLS-chain controls.
Test a proposed replacement with its own compiler and corresponding
`TRUST_EXPECTED_GO_SDK`; a numerically newer release is not proof of protection.
For a reproducible contrary control, run the same executable with an installed,
genuine Go 1.27.1 binary:

```sh
env -u GOROOT GOWORK=off GOTOOLCHAIN=local TRUST_EXPECTED_GO_SDK=go1.27.1 \
  /path/to/go1.27.1/bin/go -C infra/certificate-trust run .
```

Expected: nonzero exit with `did not enforce the intermediate-key deny` and
`<nil>` as the verification result. This is an accepted incident certificate,
not a missing-root or network error. No additional fixture or aggregate-branch
file is needed to reproduce it.

## Limits and follow-up

- Twelve-key evidence is not twelve-key enforcement: the Go probe establishes
  eight direct intermediate checks and six non-leaf TLS checks with explicit
  roots, not root-key denial, default OS stores, Darwin's platform-delegated
  verifier or every TLS factory. The two code-signing intermediate keys lack
  non-leaf public witnesses here, so their code-signing path behavior is not
  qualified by this probe. A test requires those two CA certificates to permit
  code signing but neither server authentication nor any usage; their exclusion
  does not rely merely on inventory labels. The TLS witnesses cover position 1
  only, not deeper intermediate or cross-signed paths.
- The direct controls' issuer signatures use the emSign TLS and CS roots. The
  AAA and ECC roots are public DER/policy evidence, not issuer-used or root-key
  rejection controls in this fixture set. Trust-anchor self-signature algorithms
  are not weakened merely to validate evidence; the public AAA root uses SHA-1.
- Root-store removal is containment, not a verifier fix. This change neither
  filters stores nor updates compilers, images or independently shipped clients.
- Later owner PRs can use this policy, add their own path/enforcement and policy
  synchronization tests, and adopt narrowly scoped store-filtering helpers.
  Those integrations must preserve ordinary hostname, signature, validity,
  usage, critical-extension and enterprise-root verification.
- Builds, signed/released artifacts, installed processes and fleet rollout need
  their own evidence and authorization. Source/test success does not upgrade
  existing clients or close the exposure. Retained vulnerable trust is not
  evidence of exploitation.

The aggregate PR remains unmerged while its independently reviewable pieces are
extracted. Nothing here publishes an artifact, deploys a workload or authorizes
merging that aggregate change.
