# Tuist Code

Once workspace for Tuist Code, a Rust-core client developed alongside the shipping apps in `../app/` and `../android/`. It reports to the Tuist project `tuist/code`. Native frontend sources live in `apple/`, `ios/`, `macos/`, and `android/`; the GPUI desktop frontend lives in `gpui/`. Keep shared business logic in Rust crates, platform UI in Swift/Kotlin/GPUI, and UI dependencies out of the shared core. See `README.md` for build commands and coexistence boundaries.

The apps display as **Tuist Code** and use the `dev.tuist.code` identity (bundle ID, Android application ID and package, Linux app ID) with the `tuist-code://oauth-callback` scheme. Distribution is internal-preview-only: no store uploads, public releases, production OAuth/deep-link registrations, or changes to shipping client behavior.

New Apple copy belongs in `apple/Resources/en.lproj/Localizable.strings`; new Android copy belongs in `android/res/values/strings.xml`. Platform code owns localization; the Rust core exposes stable destination IDs through the C/JNI bridge. Once builds must not import Swift CLI modules or the shipping Gradle app. Run tasks with the root mise config excluded as documented in the README.
