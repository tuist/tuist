# Kura key security

This boundary contains root-custody policy generation, admission regression
checks and the migration/recovery runbook. Parent: `../AGENTS.md`.

- Never read or print live root keys, passphrases, projected tokens or backup
  credentials. Access audits inspect RBAC/vault membership and references only.
- `kms-policies.rb` generates JSON from explicit non-secret inputs; it does not
  provision AWS. Keep the workload role limited to Encrypt/Decrypt with context,
  and keep administrative authority separate. Pin full key ARNs, not aliases.
- `admission_test.rb` is ONLY for the disposable `kind-kura-key-security`
  cluster. It deliberately grants a local fixture identity cluster-admin to
  test admission independently of RBAC. Never run it on hosted clusters.
- Root rewrap preserves plaintext shares, order and versions. Adding/removing a
  composite share is a different operation requiring volume key migration.
- Live row inventory is insufficient to retire a root. Include retained backup
  recovery points, old releases and already-open volume mappings.
- Keep `key-management.md` honest about implemented/local-tested versus live
  deployed. Do not claim AWS custody or audit verification from mocked tests.
