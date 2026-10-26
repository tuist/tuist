# Android emulator macOS smoke

Standalone, dependency-free Java Android app and emulator driver for
`../../workflows/android-emulator-macos.yml`. Reuse the repository's
`android/gradlew` wrapper with `-p .github/scripts/android-emulator-smoke`; do not
couple this fixture to the production Android app or Tuist credentials.

The manual workflow targets `tuist-macos`. Default to SwiftShader to isolate GPU
limitations, but require real HVF CPU acceleration and report unsupported nested
virtualization rather than silently changing runner shape or disabling acceleration.
Keep all device waits and diagnostic collection bounded. A successful smoke must
prove the app is foregrounded, handles input, and produces a decodable video.

Run portable driver tests with
`python3 -m unittest discover -s .github/scripts/android-emulator-smoke -p '*_test.py'`.
The actual emulator run must be validated separately on the managed profile;
local builds and mocks are not evidence that nested virtualization works there.
