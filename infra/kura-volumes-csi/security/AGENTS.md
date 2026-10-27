# Kura key security

This boundary contains OpenBao configuration generation, admission regression
checks and the migration/recovery runbook. Parent: `../AGENTS.md`.

- Never read or print live root keys, passphrases, projected tokens or backup
  credentials. Access audits inspect RBAC/vault membership and references only.
- `openbao-config.rb` generates reviewable JSON from non-secret inputs; it makes
  no API calls. The workload gets only Transit encrypt/decrypt, with exact key
  paths and environment-bound Kubernetes identity. Keep administration separate.
- `openbao_integration.rb` creates its own `kind-kura-openbao-security` cluster
  and refuses reuse. It uses real TLS, Kubernetes login, Transit and Raft. Its
  single-node emptyDir storage and one-share unseal fixture are LOCAL TEST ONLY.
  Never use its initialization, root token or deployment as a hosted template.
  Fixture credentials and plaintext stay in a private temp directory or memory;
  do not print subprocess output or commit generated results. Always clean up.
- `admission_test.rb` is ONLY for the disposable `kind-kura-key-security`
  cluster. It deliberately grants a local fixture identity cluster-admin to
  test admission independently of RBAC. Never run it on hosted clusters.
- Root rewrap preserves plaintext shares, order and versions. Adding/removing a
  composite share is a different operation requiring volume key migration.
- Live row inventory is insufficient to retire a root. Include retained backup
  recovery points, old releases and already-open volume mappings.
- Keep `key-management.md` honest about implemented/local-tested versus live
  deployed. OpenBao has no automatic HSM boundary: document the seal and backup
  custody. Never store unseal shares alongside the application or claim hosted
  recovery/audit verification from local tests.
- The disposable staging proof in `key-management.md` loaded production source
  in an isolated release process and manually reopened a LUKS file on a
  diagnostic CSI LV. It is not a full server-image/CSI key-endpoint cutover,
  persistent tenant-key migration, or durable OpenBao deployment.
