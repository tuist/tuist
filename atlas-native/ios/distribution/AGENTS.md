# Atlas iOS device distribution

`bundle.sh` signs a copy of `AtlasIOSDevice` using the existing Tuist distribution
certificate and Atlas-specific ad-hoc profile from 1Password. Keep this Bash-only;
use macOS `security`, `plutil`, PlistBuddy and `codesign` rather than a separate
profile-validation framework.

- Keep private keys in a temporary keychain and remove credentials on exit.
  `keychain.sh` adds it to the user search list for signing and restores the exact
  original list before deletion, including on failure. `codesign --keychain` alone
  does not make it available for certificate-chain lookup. Never import keys into
  the login keychain or mutate Once's cached output.
- Check the Atlas app identity, ad-hoc profile expiration and matching signing
  certificate. Use the profile's entitlements with Atlas-only Keychain access.
- Only the protected main-branch publication job receives distribution secrets.
  Device enrollment and vault references are in the [README](../../README.md).
- `version.sh` stamps only delivery copies with `ATLAS_BUILD_VERSION`, defaulting
  to the current Unix timestamp for local packaging. CI selects one fresh version
  per publication attempt for both iOS platforms, even when Once reuses a binary.
  `simulator.sh` stamps the extracted simulator delivery bundle and re-signs it
  ad-hoc, preserving its Keychain entitlement, before installation and upload.
  Device packaging stamps its temporary copy before distribution signing.
- Validate on macOS with `python3 ios/distribution/keychain_test.py`,
  `python3 ios/distribution/version_test.py`, `bash -n`, ShellCheck and an actual
  distribution-signing run. The credential-free tests cover ordered search-list
  restoration, paths with spaces, an empty list, setup/import failures, version
  stamping without cache mutation, and real ad-hoc signature/entitlement preservation.
  Signature verification does not establish installation on a registered physical device.
