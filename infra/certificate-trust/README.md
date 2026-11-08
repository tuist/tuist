# Certificate policy and public-store tools

Extracted from [#14511](https://github.com/tuist/tuist/pull/14511), snapshot
`e2efb26eb30c0c7657601c62dd9270551f94f090`. This foundation shares policy evidence
and build-time tools, not a universal trust store or application TLS client.
It does not install trust, deploy, or qualify running services.

## Policy and provenance

`policy.json` identifies twelve eMudhra keys (four root and eight intermediate
keys) by SHA-256 of DER SubjectPublicKeyInfo, with the actual DER and source URLs.
The five public PEM fixtures under `controls/` cover all twelve keys, a distinct
AAA cross-sign of an affected intermediate, and an unrelated ISRG Root X1/R11
positive chain. Tests independently parse/hash the DER and match the certificates.
The keys, DER and public fixtures are unchanged from the source snapshot. The
intermediate source URL now points to `impacted-intermediates.json`: the source's
`intermediates.json` returns 404. The current incident JSONs match all twelve keys.

Root removal is containment, not a replacement for patched verification libraries
or Apple trust updates. An intermediate can carry an affected key even when its
root remains trusted. Preserve native/enterprise anchors and ordinary certificate
and hostname verification in each consumer.

## Stable tool contracts

Keep these files together under `infra/certificate-trust/` (or copy the scripts
beside `policy.json` into a build stage):

- `bash pem-store.sh check FILE...`: returns nonzero for affected, unreadable,
  malformed or empty stores. Checks every input until an invalid input stops it.
- `bash pem-store.sh filter SOURCE DESTINATION`: removes certificates matching
  any of the twelve keys. Retains unrelated public/private CA certificates and
  their TRUSTED CERTIFICATE AUX records. Refuses private-key material, affected
  TRUSTED CERTIFICATE records, empty results and source/destination aliases.
  The caller owns installation and permissions of the separate output file.
- `bash pem-store.sh extract-blocked SOURCE DIRECTORY`: exports affected public
  certificates as `<spki-sha256>.pem` (one file per key). It succeeds with no
  matches. Existing files for unrelated keys are not removed; use a fresh output
  directory. Cross-signs with the same key share a filename.
- `bash java-store.sh check|filter PUBLIC_CACERTS`: only public SDK stores with
  password `changeit`. Refuses identities, unsupported entries and hardlinks.
  Filtering deletes only affected trusted-certificate aliases in a staged copy,
  then independently checks its PEM export before replacing the resolved target.
  Symlinks, file metadata, JKS/PKCS12 format and passwordless PKCS12 readability
  are preserved. Private/enterprise CA anchors remain; stores containing private
  keys are refused without modification. This is not an identity migration tool.

PEM tools need Bash (including macOS system Bash), OpenSSL and awk plus standard
Unix utilities. Java tools also need `keytool`, `realpath` and `stat`. No Python,
jq, Go or network access is needed to filter stores. Consumers must wire both
their build-time and runtime trust boundaries through their own build contexts
and release detection; sharing these tools alone does not change any client.

## Independent qualification

From this directory, with Go 1.26.10, OpenSSL and JDK 21 on PATH:

```sh
GOWORK=off GOTOOLCHAIN=local TRUST_EXPECTED_GO_SDK=go1.26.10 go test -count=1 ./...
GOWORK=off GOTOOLCHAIN=local TRUST_EXPECTED_GO_SDK=go1.26.10 go run .
bash -n pem-store.sh && bash -n java-store.sh
```

`verify-go.go` checks eight distinct, cryptographically valid intermediate-key
controls with explicit roots at valid times, plus an unrelated accepted
ISRG chain. `TRUST_EXPECTED_GO_SDK`, when set, must match the compiled SDK exactly.
Qualify replacement SDKs by actual behavior, not version ordering. This probe
does **not** prove full twelve-key application enforcement, leaf denial, hostname
checks, or nil-root Darwin/Security.framework behavior.

The foundation workflow tests only this directory with read-only permissions.
The aggregate source's client policy synchronization, transport-factory wiring,
repository-wide SDK pins, management replacement guards, OTP and Kura integration
checks belong with those integrations as they land. They are not replaced by
skips or passing placeholders here. Product/runtime/artifact qualification and
owner-approved release/rollout remain separate gates.

The infrastructure SDK integration requires Go 1.26.10 in the root workspace
and every independently built infrastructure module, including the nested
GitLab executor and macOS host payloads. It retains `godebug default=go1.25`
(`go1.23` for kube-impersonator) to avoid changing unrelated runtime defaults.
The workflow runs the explicit-root probe under both retained defaults and
checks these module directives. Grafana's separate workspace has its own owner.
Go 1.26.10 also filters returned Darwin platform chains in `crypto/x509`, but
Linux tests and Darwin cross-compilation do not qualify nil-root native trust.
Existing artifacts must be rebuilt; no image or host rollout follows from a
module directive alone.

First-party Docker compiler stages select Go 1.26.10 alongside these module
floors; otherwise `GOTOOLCHAIN=local` in older builder images refuses to build.
Alpine builders use the available `1.26.10-alpine3.23` tag independently of the
unchanged runtime Alpine version. The CAPI provider pins only its first-party
compiler stages here, leaving its third-party payload stages unchanged. These
compiler selections do not filter OS stores or add build contexts; those image
trust boundaries and their rollout qualification remain separate changes.
