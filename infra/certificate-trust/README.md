# eMudhra certificate policy and offline qualification

This is the shared policy foundation extracted from [PR #14511](https://github.com/tuist/tuist/pull/14511).
It adds public evidence and an offline verifier probe, not a rollout or a change
to any production application's certificate validation.

## Policy and evidence

`policy.json` records twelve SHA-256 fingerprints of complete DER-encoded
SubjectPublicKeyInfo values, with the exact DER encoded as base64: four root
keys and eight intermediate keys. Match keys, not certificate names or whole
certificate fingerprints; a cross-sign can reuse the same public key.

The policy's `sources` identifies the public incident root/intermediate
inventories, the Go 1.26.10 change and Rust WebPKI release. The checked-in
`controls/issuer-roots.pem` and `controls/distrusted-intermediates.pem` are
public certificate evidence for those four and eight keys respectively.
`controls/positive-isrg-root-x1.pem` and `controls/positive-isrg-r11.pem`
provide an unrelated signed chain. Tests verify every policy DER/hash against
exactly one negative certificate, the four/eight split, CA roles and signatures.
No compromised private keys are needed or included.

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
credentials. It installs the toolchain, then performs the qualification offline.

The probe restores the incident issuers as explicit trust anchors, checks that
each intermediate has a cryptographically valid issuer and a shared validity
window, then requires the qualified Go verifier's specific rejection. It also
requires the unrelated ISRG intermediate to verify. Otherwise a missing root,
an expired certificate or failure to parse a fixture could masquerade as a
successful negative control.

Go 1.26.10 passes all eight intermediate controls. Test a proposed replacement
with its own compiler and corresponding `TRUST_EXPECTED_GO_SDK`; a numerically
newer release is not proof of protection. The existing Go 1.27.1 control accepts
an incident intermediate and therefore fails this qualification.

## Limits and follow-up

- Twelve-key evidence is not twelve-key enforcement: the Go probe establishes
  the eight intermediate-key checks with explicit roots, not root-key denial,
  default OS stores, Darwin's platform-delegated verifier or every TLS factory.
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
