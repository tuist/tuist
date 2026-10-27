# Kura volume keys

Parent: `../AGENTS.md`. This boundary owns tenant-share envelopes, deterministic
volume passphrases and key-service sealing.

- Only `aws_kms` and legacy `tuist_root` are implemented. Do not conflate a
  Tuist-managed KMS wrapper with organization-controlled CMEK.
- Authenticate/bind tenant, version and share position in every provider.
  Pin and allowlist full KMS ARNs, verify response ARN and 32-byte share length.
- Dedicated OIDC workload identity must not inherit S3 credentials. Never put
  plaintext shares, tokens or provider response bodies in telemetry/errors.
- Rewrap preserves shares byte-for-byte and commits with compare-and-swap only
  after verification. Do not hold DB locks while calling KMS. Preserve existing
  versions for volumes and retain source wrappers for backup recovery.
- Adding/removing a share or rotating a compromised share requires a separate
  volume/keyslot migration. Rewrap alone does not remediate leaked plaintext.
- An already-mounted LUKS volume remains accessible after key-service denial.
  Never promise immediate revocation or protection against a privileged node.
