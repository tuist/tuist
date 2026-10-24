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
  `associated-domains.sh` requires profile authorization for `applinks:atlas.tuist.dev`
  (or the profile wildcard) before fetching the private certificate, then requests
  only that exact domain in the signature. Apple profiles may authorize this as
  a scalar wildcard/exact domain or an array; accept both formats, reject malformed
  types, and normalize only the signing copy to a one-domain array. Regenerate a
  profile only when authorization is actually missing; do not invent an unauthorized
  entitlement. The unsigned Once
  device build does not require distribution capabilities.
- `push.sh` additionally requires a production `aps-environment` in the profile before reading the distribution certificate. Enable Push Notifications on the Atlas App ID and regenerate the ad-hoc profile. `bundle.sh` copies that authorized entitlement and stamps `AtlasPushEnvironment=production` into the temporary signing copy only. Unsigned device builds remain unconfigured; simulator builds use development/sandbox. Validate the credential-free guard with `python3 ios/distribution/push_test.py` on macOS. Never invent a production entitlement for an old profile.
- Only the protected main-branch publication job receives distribution secrets.
  Device enrollment and vault references are in the [README](../../README.md).
- Validate with `python3 ios/distribution/keychain_test.py`,
  `bash ios/distribution/test-associated-domains.sh` (16 macOS fixtures), `bash -n`, ShellCheck
  and an actual signing run. The credential-free tests cover ordered search-list
  restoration, paths with spaces, an empty list, and setup/import failures.
  Signature verification does not establish installation on a registered physical device.
