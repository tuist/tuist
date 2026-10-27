# Atlas Android distribution

Once builds debug-signed APKs for CI and local smoke tests. Protected main-branch
publication re-signs a copy with a stable private key via `sign.sh`, verifies the
APK, and checks its public certificate against the same fingerprint allowlist as
the server's Digital Asset Links document. Never publish ephemeral debug keys in
`assetlinks.json`, re-sign Once's cached output in place, or upload credentials.

- Keep this Bash-only and use Android SDK build-tools 35.0.0 `apksigner`.
- Configure the `atlas-mobile-previews` GitHub environment variables
  `ATLAS_ANDROID_KEYSTORE_REF`, `ATLAS_ANDROID_KEYSTORE_PASSWORD_REF`,
  `ATLAS_ANDROID_KEY_ALIAS`, and `ATLAS_ANDROID_APP_LINK_SHA256`. References point
  to 1Password material readable by the existing protected service account.
  No key reference means Android nightly publication is deliberately skipped;
  debug CI artifacts remain available. Incomplete configured signing fails.
- Provision a stable PKCS#12 keystore once, not once per workflow. Use the same
  password for its store and private key. Back it up securely; switching keys
  without Android signing lineage normally requires users to uninstall the old
  app. Debug-signed installed builds must also be uninstalled before moving to
  the stable distribution identity. Never generate a real distribution key in
  an untrusted build job or an agent fixture.
- Trusted fingerprints use uppercase colon-separated SHA-256 bytes, comma-
  separated for multiple keys. Keep server and CI configuration identical. A
  verification fingerprint only authorizes link handling; adding one does not
  make Android accept an incompatible APK update. See the server
  [deployment guidance](../../../atlas/deploy/AGENTS.md#native-app-links).
- Fetch secrets only into a restrictive temporary directory, pass passwords via
  files rather than command arguments, remove all material on every exit, and
  publish only after `apksigner verify` and fingerprint checks succeed.
- `python3 android/distribution/sign_test.py` is credential-free shell
  orchestration coverage with fake tools/material. Also run syntax/ShellCheck
  and a real `apksigner` smoke with a disposable test key, never promote that key
  into production trust. Live domain verification requires the deployed
  association document and installed stable-key build.
