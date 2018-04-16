import Foundation

fileprivate class Dummy {}

// MARK: - Bundle (Extras)

extension Bundle {
    /// Returns the application bundle. Since this variable is accessed from the cli, using Bundle.main wouldn't return the expected bundle.
    /// We use a dummy clase contained in this bundle to get the framework bundle and then we get the app's from that one.
    static var app: Bundle {
        let path = Bundle(for: Dummy.self).bundleURL
        let appBundlePath = path.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return Bundle(url: appBundlePath)!
    }
}
