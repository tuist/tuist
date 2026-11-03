# Kura volume keys

Parent: `../AGENTS.md`. This boundary owns tenant-share envelopes, deterministic
volume passphrases and key-service sealing.

- Only `openbao` and legacy `tuist_root` are implemented. Do not conflate a
  Tuist-managed KMS wrapper with organization-controlled CMEK.
- Authenticate/bind tenant, version and share position in every provider.
  Pin the HTTPS origin, Transit mount and key name; allowlist decrypt keys and
  verify exactly 32 plaintext bytes. Bind both Transit context and associated data.
- Dedicated Kubernetes workload identity uses OpenBao login, with no static
  workload token or cloud credentials. Never put
  plaintext shares, tokens or provider response bodies in telemetry/errors.
- Rewrap preserves shares byte-for-byte and commits with compare-and-swap only
  after verification. Do not hold DB locks while calling OpenBao. Preserve existing
  versions for volumes and retain source wrappers for backup recovery.
- Reverse migration sets `kuraVolumeOpenBao.wrapNewShares=false` while keeping
  OpenBao configured for decrypt. Wait for every web replica to adopt it before
  rewrapping; disable OpenBao only after inventory and re-stage checks pass.
- Adding/removing a share or rotating a compromised share requires a separate
  volume/keyslot migration. Rewrap alone does not remediate leaked plaintext.
- Issuance must stay independent of TLS terminators: TokenReview only for the
  audience derived from the request key, and seal with the pinned transport key
  plus volume id and key version as AAD. Never accept a key-independent audience.
- An already-mounted LUKS volume remains accessible after key-service denial.
  Never promise immediate revocation or protection against a privileged node.
