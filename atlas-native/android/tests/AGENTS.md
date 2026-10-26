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
- Test the default native network-security-config manager, accepted-chain
  leaf/anchor add-only denies, twelve public certificate-specific negatives,
  unrelated HTTPS, and protected-factory redirect settings. Timeouts or network
  failures are not certificate rejection. Do not log credentials or bodies.
- These checks do not execute the UI favicon redirect loop, qualify private or
  CT-enabled custom NSC, older APIs, physical devices, R8 or signed releases.
  Preserve reflective extended trust-manager methods before adding minification.
- No Python, account login, host trust installation, global TLS defaults or
  certificate-validation bypasses. See `../../../infra/certificate-trust/RUST-CLIENTS.md`
  for the dated evidence and release gates.
