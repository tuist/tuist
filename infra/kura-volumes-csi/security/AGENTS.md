# Kura key security

This boundary contains admission regression checks, Helm checks and the
root-key rotation/recovery runbook. Parent: `../AGENTS.md`.

- Never read or print live root keys, passphrases, projected tokens or backup
  credentials. Access audits inspect RBAC/vault membership and references only.
- `admission_test.rb` is ONLY for the disposable `kind-kura-key-security`
  cluster. It deliberately grants a local fixture identity cluster-admin to
  test admission independently of RBAC. Never run it on hosted clusters.
- Root rewrap preserves plaintext shares, order and versions. Adding/removing a
  composite share is a different operation requiring volume key migration.
- Live row inventory is insufficient to retire a root. Include retained backup
  recovery points, old releases and already-open volume mappings.
- Keep `key-management.md` honest about implemented/local-tested versus live
  deployed. Never claim hosted recovery/audit verification from local tests.
