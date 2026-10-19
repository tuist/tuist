# Atlas iOS device distribution

`bundle.sh` signs a copy of `AtlasIOSDevice` using the existing Tuist distribution
certificate and Atlas-specific ad-hoc profile from 1Password. Keep this Bash-only;
use macOS `security`, `plutil`, PlistBuddy and `codesign` rather than a separate
profile-validation framework.

- Keep private keys in a temporary keychain and remove credentials on exit.
  In CI, select it as the default before importing the certificate, following
  `mise/tasks/app/bundle-ios.sh`. Save the prior default before creating the
  keychain and restore it on exit, including failures and cancellation. If CI
  had no default, restore that state. Local runs must not change the default.
  Never mutate Once's cached output or import keys into the login keychain.
- Check the Atlas app identity, ad-hoc profile expiration and matching signing
  certificate. Use the profile's entitlements with Atlas-only Keychain access.
- Only the protected main-branch publication job receives distribution secrets.
  Device enrollment and vault references are in the [README](../../README.md).
- Validate with `bash -n`, ShellCheck and an actual signing run. Signature
  verification does not establish installation on a registered physical device.
