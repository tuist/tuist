# Atlas build modules

`firebase.star` exposes locked official Android Firebase/AndroidX jars and compiled
AAR resources through Once's `android_library` provider. It generates library-package
R classes with the same resource set as the application. `build:android` must run
`android/push/resources.py verify` against the final APK: a successful compilation
alone does not prove resource IDs match. SDK manifests are explicitly merged and
audited; see [Android push packaging](../android/push/AGENTS.md). Materialized Maven
sources live in `.once/vendor-maven`, separate from Cargo's `.once/vendor` cleanup.
Do not remove these gates or substitute a handwritten FCM protocol.

`apple.star` exports a small `apple_linkable` provider through Once's public
module API. The device/simulator SDK targets resolve the selected macOS Xcode
SDK with `xcrun` and forward it to Darwin Clang as joined `-isysroot<path>`.
Once 0.68.2's Swift driver otherwise stamps the deployment version as the SDK;
the joined spelling survives its linker-option deduplication. No built-in rule
is copied or overridden. Keep production and preview apps dependent on the
matching SDK target. Remove this workaround when a published Once fixes linking.

The workspace currently requires macOS for iOS builds and does not set a custom
`xcode_developer_dir`. Keep SDK discovery consistent with the built-in compiler
selection if introducing such an override. Host probes participate in analysis
observations and the resolved linker argument participates in action identity.

`widget.star` exports `atlas_widget_extension` for Once 0.68.2. Required attributes
are `sdk_variant` (`simulator` or `device`), `bundle_id` (production or Settings
preview Live Activity ID), and `info_plist`. Supply the shared activity attributes,
renderer and WidgetBundle entry point as Swift-only `srcs`; there are no assets or
transitive libraries. It emits arm64/iOS-17 `AtlasLiveActivity.appex`, substitutes
the three `ATLAS_ACTIVITY_BUNDLE_ID`, `ATLAS_SUPPORTED_PLATFORM` and
`ATLAS_PLATFORM_NAME` plist variables, and ad-hoc signs the complete tree. Link with
`_NSExtensionMain` for system extension startup and explicitly retain Swift's `_main`
with `-u` alongside its `__swift5_entry` metadata. Direct Swift startup exited
without serving WidgetKit descriptors in the iOS 26.5 simulator. Set both Swift's
`-application-extension` and the linker's `-application_extension` safety flag.
Compiler/frontend/Clang/linker bytes, SDK and toolchain library
trees identify the action and isolate its cleaned module cache. Do not copy private
Once prelude helpers or weaken this identity to a version string.

The same rule also accepts `dev.tuist.atlas.share`, producing `AtlasShare.appex`
from `ios/Share/*.swift` with UIKit/Social instead of WidgetKit. Its Objective-C
principal class uses `_NSExtensionMain` directly, with no Swift `@main` retention.
Only Share receives the exact App Group entitlement. Both production hosts depend
on and embed their matching Share target; the isolated Settings preview does not.
`embed-widget.sh` accepts only the two known extension names and preserves siblings.

Run `/bin/bash modules/check-widget.sh <path-to-AtlasLiveActivity-executable>` on
macOS for the built production simulator, device, and Settings preview extensions.
This public Mach-O gate uses `xcrun nm` and `otool` to require a defined Swift
`_main`, nonempty `__TEXT,__swift5_entry`, and an `LC_MAIN` file offset mapping to
the `_NSExtensionMain` indirect-symbol stub in `__TEXT,__stubs`, not its pointer
entry or Swift main. This is a runtime-startup contract, not a compiler/linker flag
check: direct Swift entry can compile and exit successfully without serving
WidgetKit. Keep this gate separate from `check-sdk.sh`, which validates the
selected SDK and minimum iOS version. New build automation must use Bash.

Each host must depend on its matching extension target and declare a cacheable
`postbuild_actions` embedding hook before Once signs the host. Once stages the
dependency as `<host build_dir>/AtlasLiveActivity.appex`; declare that tree and
`modules/embed-widget.sh` as hook inputs and the final
`<host build_dir>/<product>.app/PlugIns/AtlasLiveActivity.appex` as its output.
Invoke `/bin/bash modules/embed-widget.sh` with either source/destination arguments
or `ATLAS_WIDGET_SOURCE`/`ATLAS_WIDGET_DESTINATION` environment values. For Once's
configured build directories, set the hook's `build_dir` to its declared directory
and use absolute workspace-prefixed environment paths: Once rebases those and the
declared inputs/outputs, but not argv strings. Keep embedding confined to the host
copy, not the extension's cached output. Distribution profile checks and inside-out
re-signing live in [iOS distribution](../ios/distribution/AGENTS.md).

`nsh.star` imports NSH 0.2.0's checksum-pinned release XCFramework slices and
resource-free Android AAR through Once's public provider contracts. Downloads and
AAR extraction are explicit cached actions, never analysis-time network calls.
The adaptation references the pinned Once provider sources and their hashes;
recheck those when upgrading. It also checks `cards/verify.py` before either
mobile build so stale generated UI cannot ship. Resolve the real Python
interpreter before sandbox execution, not a Mise shim that needs the parent PATH.
Keep NSH out of the navigation/CLI/auth dependency closures. Android packages the
arm64 runtime but instantiates it only on API 28+, retaining API-26 text fallback.
Do not raise the app minimum or add Gradle. After SDK upgrades test actual card
rendering alongside Atlas's Rust auth library, not just framework linking.

Validate graph, device/simulator builds, `check-sdk.sh`, and rendered preview
after Once upgrades. Require the actual selected SDK and iOS 17 minimum on
packaged binaries. Do not raise minimum OS, fake plist provenance, or draw a
custom glass bar merely to enable the current system appearance.
