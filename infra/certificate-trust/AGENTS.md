# Certificate policy and verifier qualification

This boundary owns the twelve-key eMudhra SPKI policy, public certificate
fixtures and offline Go verifier qualification. Read `README.md` before extending
its scope. It is the first extraction from PR #14511, not a deployment tool.

- Keep four root and eight intermediate keys, their exact SPKI DER and public
  certificate evidence synchronized. Test signatures and unrelated positives,
  not only JSON shape or certificate names.
- Qualify an SDK by actual verification behavior. Do not infer protection from
  release-number ordering. Go 1.26.10 passes these eight intermediate controls;
  this does not qualify all twelve keys, native delegated paths or applications.
- Use the isolated module with GOWORK=off and GOTOOLCHAIN=local. Unset inherited
  GOROOT when selecting a compiler. Keep TRUST_EXPECTED_GO_SDK and CI aligned.
- Tests and the executable must remain offline, credential-free and independent
  of the surrounding repository, installed applications and native CA stores.
- No Python tooling/tests, generic overlay/publisher, trust-store mutation,
  network probes, package publication, deployment or registry credentials.
- Do not use compromised private keys. Fixtures contain public certificates only.
- Owner-specific TLS enforcement, SDK/image updates, store filtering, signed
  releases and safe warm rollout belong in separate reviewed changes.
