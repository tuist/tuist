# Atlas macOS distribution

`prepare-app.sh <Once source.app> <new runnable.app>` copies Once's flat
Apple bundle into the macOS `Contents/{MacOS,Resources,Frameworks}` layout and
ad-hoc signs the copy. Use `.once/macos/Atlas.app` locally; the isolated preview
retains its own bundle identifier and executable from its source plist. A caller
must remove its disposable destination before repeating preparation. Never move
or re-sign cached source outputs. `prepare.sh` is the production-only wrapper
that additionally requires Atlas's identity. `validate.sh` checks the macOS 14 minimum,
selected Xcode SDK, URL scheme, Atlas-only feed, framework linkage/runpath and
complete versioned Sparkle helpers. It also requires the declared `Atlas.icns`
resource to decode as ICNS; packaging fixtures reject absent/misnamed declarations
and missing/corrupt icons and preserve the icon in production and preview copies.
`sign.sh <Atlas.app> -` ad-hoc signs a local
copy for credential-free launches without hardened-runtime library validation,
which cannot authenticate ad-hoc frameworks by team identity. Developer ID builds
always use hardened runtime; never add disable-library-validation to distribution
entitlements. The updater starts only in the production app, not preview apps.

`bundle.sh <prepared Atlas.app> <new output directory> <epoch build>` uses Tuist's
existing Developer ID certificate and Apple notarization account. It imports the
key only into the existing iOS helper's temporary-keychain lifecycle, restores
the exact original search list on all exits and never changes the default
keychain. It stamps only its temporary copy, signs nested Sparkle helpers before
the framework and app, submits notarization, requires Accepted, staples and
validates before creating the final `Atlas-macos.zip`. Hardened runtime requests
audio input plus profile-authorized macOS APNs/identity entitlements; there is no
app sandbox, disable-library-validation entitlement or Live Activity.
`--deep` is verification only, never a signing shortcut.

## Developer ID push provisioning

Desktop release signing now requires a **separate** Apple-issued, Push-enabled
Developer ID provisioning profile for `dev.tuist.atlas`, the same App ID as iOS.
An authorized operator must enable Push Notifications on that shared App ID under
team `U6LC622NKF`, create/regenerate its Developer ID profile authorizing the
existing Tuist Developer ID Application certificate, and store the downloaded file at
`op://tuist/Atlas macOS Developer ID/Atlas_macOS_Developer_ID.provisionprofile`.
Grant the protected release service account read access to it. Never reuse the
iOS ad-hoc profile or a Mac App Store/development profile. No device registration
is required for Developer ID distribution.

`push.sh` validates the CMS-decoded profile before any private-certificate read:
Mac platform (`Platform = [OSX]`), all-device Developer ID provisioning, exact
Atlas App ID and Tuist team, typed production `com.apple.developer.aps-environment`,
creation/expiration dates, no debugging entitlement, and current Developer ID
Application certificates with matching subject/team and certificate purpose.
It matches an authorized certificate fingerprint against the valid imported
private identities, not merely a certificate display name or array index zero.
The signed app's actual certificate, team and exact entitlement set are checked
again. Derive the App ID prefix from the profile; a legacy prefix need not equal
the team. Only the temporary delivery copy receives
`Contents/embedded.provisionprofile` and `AtlasPushEnvironment=production`.
The signature requests only profile-derived macOS APNs/App ID/team and existing
microphone access, not every capability allowed by the profile.

See Apple's [macOS APNs entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.aps-environment)
and [provisioning profile guidance](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles).
Missing or invalid provisioning fails before notarization and publication, never
falls back to an unconfigured release. Local ad-hoc builds intentionally have no
profile, APNs entitlement or configured-push plist marker. `prepare-app.sh`
strips those from its copy even when preparing a previously distributed app;
it never mutates its source. `validate.sh` defaults to that credential-free
contract; `--distribution` requires the embedded profile and production marker.
The backend must separately opt in to macOS delivery on the shared topic
`dev.tuist.atlas` with authorized production APNs credentials. Packaging alone
does not enable server delivery or prove notification consent/foreground/background behavior.

`fetch-sparkle.sh` downloads the same checksum-pinned official release as
`modules/sparkle.star` for publishing tools. Keep both pins identical.
`appcast.sh` reads the same Tuist Sparkle signing-key reference as app-release,
uses a disposable archive copy, checks epoch monotonicity against the live feed,
and validates the new signed enclosure URL/build/byte length before exposing the
output feed. Preserve prior entries and their immutable download URLs. Only
`atlas-macos-release.yml`, called after native build/test/lint/packaging gates on
trusted main, receives distribution credentials. No credential enters a cached
action or a PR job. Publish the immutable `atlas-macos@<epoch>` payload before
replacing `atlas-appcast/atlas-appcast.xml`. Never overwrite an existing payload.
An initial missing feed is bootstrapped by that publication; network/provider
errors must not be mistaken for a missing feed. These are Apple silicon releases,
not universal binaries. Keep credentials out of PR builds and cached artifacts.

Run `bash macos/distribution/test-packaging.sh` (includes `test-push.sh`),
`bash -n`, ShellCheck, module validation and a real local Once build before
merging. Tests require macOS's plist tools but no provider credentials.
After `once build AtlasSparkle`, run
`bash macos/distribution/test-framework-boundary.sh .once/out/AtlasSparkle/sdk/Sparkle.framework`.
This offline fixture uses real ad-hoc codesign on disposable copies: an invalid
root signature directory must fail, while the extraction action's forwarding
symlink must survive copying/output-parent preparation and pass strict deep
verification with all nested helpers present. It checks that the cached source
is unchanged. `test-appcast.sh <Sparkle SDK> <prepared Atlas.app>` runs the real
generator for two successive builds using disposable CryptoKit-generated keys.
It verifies archive signatures independently with CryptoKit and Sparkle, rejects
tampering/wrong keys/old builds, and checks retained feed history and source
immutability. Both checks run in trusted and fork macOS build jobs before ZIP
upload. Only the vault read is replaced in that real-tool appcast test; no
Keychain entry, production signing key or live release is used. Push fixtures
use real plist/date/X.509 tools and disposable self-signed test certificates;
CMS trust, signing identity/keychain services, notarization and vault calls are
mocked, never Apple credentials. Actual
Developer ID provisioning acceptance, notarization, signed updates, APNs token
registration/delivery, microphone permission and real-account OAuth remain
authorized release or physical-host validation, not evidence supplied by mocks
or ad-hoc signatures.
