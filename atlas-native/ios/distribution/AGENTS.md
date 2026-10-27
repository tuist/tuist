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
- `live-activity.sh` requires a device `PlugIns/AtlasLiveActivity.appex` with the
  production ID `dev.tuist.atlas.live-activity` and WidgetKit extension point before
  reading profiles. A **separate, newly required** ad-hoc profile must be supplied
  at `op://tuist/Atlas Live Activity Ad Hoc/Atlas_Live_Activity_Ad_Hoc.mobileprovision`.
  Provisioning that App ID/profile is a separate authorized human operation; the
  build and credential-free tests neither create it nor access the vault. It must
  use team `U6LC622NKF`, authorize the app's chosen distribution certificate, remain
  unexpired and cover every registered device in the host profile. All extension
  profile checks run before fetching the private certificate. Do not reuse the
  host profile or its APNs, Associated Domains or Keychain entitlements.
- Share additionally requires App ID `dev.tuist.atlas.share` and the separate ad-hoc
  profile at `op://tuist/Atlas Share Ad Hoc/Atlas_Share_Ad_Hoc.mobileprovision`.
  Enable/register App Group `group.dev.tuist.atlas.share` on both host and Share IDs,
  regenerate their profiles with the same certificate and host devices, and grant
  the publication identity access to that new profile. This is a separate authorized
  Apple/vault provisioning operation, never performed by a build. `share.sh` requires
  exact array authorization (no wildcard), narrows the signing copy to that group,
  and rejects wrong/missing bundles or profiles before private certificate access.
  The shared profile validator checks team/expiration/certificate/devices for both
  extensions; Share inherits no APNs, domains or host Keychain entitlements.
- Only the temporary distribution copy receives the extension profile and matching
  host marketing/build versions. Scan all three executables for Swift runtime libraries,
  sign libraries and nested frameworks inside-out, then sign/verify both extensions
  with its own identity-only entitlements, then sign/verify the containing app with
  its existing entitlements. `--deep` is verification only, never a signing shortcut.
  The simulator/preview ad-hoc signature is not a device distribution identity.
- Only the protected main-branch publication job receives distribution secrets.
  Device enrollment and vault references are in the [README](../../README.md).
- Validate with `python3 ios/distribution/keychain_test.py`,
  `bash ios/distribution/test-live-activity.sh`,
  `bash ios/distribution/test-associated-domains.sh` (16 macOS fixtures), `bash -n`, ShellCheck
  and an actual signing run. The credential-free tests cover ordered search-list
  restoration, paths with spaces, an empty list, and setup/import failures.
  Live Activity fixtures cover profile/device/certificate rejection, version and
  entitlement isolation, embedding cleanup, signing order/failure and credential-read
  preflight ordering through the real bundle script. These Bash fixtures run on
  macOS with real plist/date tools and fake only Xcode, signing and vault commands.
  Additionally run
  `once query validate-module modules/widget.star --format json`, build simulator
  and device targets on macOS/Xcode, run `bash modules/check-widget.sh` against
  each extension executable, inspect SDK metadata and entitlements,
  and test installation/ActivityKit rendering on a registered physical device.
  Signature verification does not establish installation on a registered physical device.
