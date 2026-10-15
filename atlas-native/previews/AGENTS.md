# Native settings screenshot previews

These independent Once targets render the production native Settings views with fixed, in-memory API responses. They make screenshots reproducible without real provider credentials, browser authentication, a public development server, or an Atlas-authorized ChatGPT client.

- Build from `atlas-native/` with `ONCE_CACHE_PROVIDER=local mise exec -- once build AtlasSettingsIOSPreview` or the Android equivalent `AtlasSettingsAndroidPreview` (with the same Android SDK/NDK environment and compiler `PATH` as the production `build:android` task).
- `ONCE_CACHE_PROVIDER=local mise exec -- once test AtlasSettingsUITests` drives the iOS preview through native Settings, Claude, and ChatGPT sign-in/cancellation. It records `ios-settings`, `ios-claude`, and `ios-chatgpt` screenshot attachments. The test log reports the result bundle; export its attachments with `xcrun xcresulttool export attachments` to a directory outside the repository. The separate UI runner depends on the preview app and never installs over the real Atlas bundle.
- The preview sources are outside both production source globs. Their bundle/application IDs end in `.settings-preview` (iOS) or `.preview` (Android). Never add preview authentication bypasses or launch-argument fixtures to production apps.
- After building the Android preview, `python3 previews/capture_android.py --adb /path/to/adb --output /tmp/atlas-settings-screenshots` installs only the preview package, verifies the secure token input and ChatGPT cancellation, and captures the three native states. It requires a booted Android emulator.
- Both targets reuse the actual Settings screens. Fixtures implement the metadata/device-login response contract, use the reserved `atlas.example.org` host and an unmistakable `DEMO-CODE`, and never perform account-management requests or enter real tokens.
- Clearly label preview-backed screenshots in pull requests. They validate native rendering and navigation, not real OAuth/device authorization or upstream inference.
- Keep screenshot images outside the source branch. Host them separately and include links in the pull request.
