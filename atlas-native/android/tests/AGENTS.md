# Atlas native certificate instrumentation

This credential-free Java instrumentation APK loads the policy from the actual
Atlas debug APK using the target class loader. Do not compile a second policy
copy into the harness or treat the main Tuist Android application's tests as
Atlas coverage.

Run only against an explicitly selected idle emulator owned by this test session:

```sh
ATLAS_TRUST_LIVE=1 ANDROID_HOME=/path/to/sdk JAVA_HOME=/path/to/jdk21 \
  bash android/tests/run-certificate-trust.sh \
  .once/out/AtlasAndroid/AtlasAndroid.apk emulator-PORT /path/to/debug.keystore
```

- SDK/platform 35 and build-tools 35.0.0 are the defaults. The harness requires
  a standard Android debug signer matching the target APK. It never re-signs
  the target, uses a production signing identity or changes device/host trust.
- Confirm emulator identity before use. The script refuses physical devices and
  an existing test package. It installs/updates the selected debug target and
  removes only the test package it installed. Starting/stopping the owned
  emulator belongs to the caller; never stop another session's device.
- Test independent real twelve-key DER against the actual APK, the default native
  network-security-config manager, accepted constructed-path leaf/intermediate/anchor
  add-only denies (including an anchor key absent from the TLS peer chain), twelve
  public certificate-specific negatives, ordinary hostname/expiry/unknown-CA
  rejection, unrelated HTTPS and the production favicon loader's healthy image
  path. Factory redirect defaults are also checked. Timeouts or network failures
  are not certificate rejection. Do not log credentials or bodies.
- These checks do not qualify denied redirect/proxy paths, private or CT-enabled
  custom NSC, older APIs, physical devices, R8 or signed releases. The isolated
  Accounts preview supplies synthetic images, not network transport evidence.
  Preserve reflective extended trust-manager methods before adding minification.
- No Python, account login, host trust installation, global TLS defaults or
  certificate-validation bypasses. Public negatives can fail native validation
  before application enforcement; only otherwise-accepted-key differentials
  establish that the application's deny executes. Fixtures contain certificates,
  not private keys, and belong only in the separately signed test APK.
