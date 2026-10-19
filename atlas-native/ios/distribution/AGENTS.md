# Atlas iOS device distribution

This leaf owns post-build ad-hoc signing and IPA packaging. The parent Once
workspace builds `AtlasIOSDevice` without distribution credentials. Keep
simulator and device Rust dependencies separate and never substitute the
simulator's Keychain entitlements for a provisioned device identity.

- `bundle.sh` copies the Once output, reads the existing Tuist distribution
  certificate and Atlas-specific ad-hoc profile from 1Password, uses a temporary
  keychain, and removes credentials/keychain on exit. Do not mutate Once outputs,
  import private keys into the login keychain, or cache/upload signing inputs.
- `profile.py` checks expiration, Tuist team, explicit production app ID, ad-hoc
  device membership, non-debug entitlements, device plist metadata and matching
  valid distribution identity. Derive application/Keychain identity from the
  profile's application prefix (which need not equal its team ID). Restrict
  entitlements to those the app needs; do not copy arbitrary profile capabilities.
- The current app has statically linked Rust and system frameworks; packaging
  copies/signs required Swift runtime dylibs before signing the app. If embedded
  frameworks/extensions are introduced, add inside-out signing and validation.
- Only the trusted main-branch publication job receives the 1Password service
  token. Never expose it to PR/fork build or test jobs. Missing/invalid signing
  inputs must fail delivery, not silently publish a simulator-only replacement.
- Setup and device-enrollment instructions live in the
  [workspace README](../../README.md). Never commit profiles, certificates,
  private keys or UDIDs as test data.

Validate without credentials with `mise run test:distribution` from
`atlas-native/` and `bash -n ios/distribution/bundle.sh`. A successful device
build or fixture test does not establish real-device installation: that requires
an authorized, registered device and a valid Apple-issued ad-hoc profile.
