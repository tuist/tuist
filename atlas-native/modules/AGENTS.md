# Atlas build modules

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

Validate graph, device/simulator builds, `check-sdk.sh`, and rendered preview
after Once upgrades. Require the actual selected SDK and iOS 17 minimum on
packaged binaries. Do not raise minimum OS, fake plist provenance, or draw a
custom glass bar merely to enable the current system appearance.
