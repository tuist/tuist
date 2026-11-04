# Kura volume keys

Parent: `../AGENTS.md`. This boundary owns tenant-share envelopes, deterministic
volume passphrases and key-service sealing.

- Only `tuist_root` is implemented. Do not conflate a Tuist-managed root with
  organization-controlled CMEK.
- Authenticate/bind tenant, version and share position in every provider and
  verify exactly 32 plaintext bytes. Never put plaintext shares, roots or
  provider errors containing key material in telemetry/errors.
- Rewrap preserves shares byte-for-byte and commits with compare-and-swap only
  after verification. Do not hold DB locks during provider calls. Preserve existing
  versions for volumes and retain source roots for backup recovery.
- Adding/removing a share or rotating a compromised share requires a separate
  volume/keyslot migration. Rewrap alone does not remediate leaked plaintext.
- Issuance must stay independent of TLS terminators: TokenReview only for the
  audience derived from the request key, and seal with the pinned transport key
  plus volume id and key version as AAD. Never accept a key-independent audience.
- An already-mounted LUKS volume remains accessible after key-service denial.
  Never promise immediate revocation or protection against a privileged node.
