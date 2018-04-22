import Basic
import Foundation

fileprivate class Dummy {}

enum BundleError: Error {
    case frameworkNotEmbedded(AbsolutePath)
}

// MARK: - Bundle Extension

extension Bundle {
    /// If xcbuddykit is embedded in the an app, this getter returns the bundle of the app where the framework is contained.
    static func app() throws -> Bundle {
        let path = Bundle(for: Dummy.self).bundleURL
        let appBundlePath = path.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        if appBundlePath.pathExtension == "app" {
            return Bundle(url: appBundlePath)!
        }
        throw BundleError.frameworkNotEmbedded(AbsolutePath(path.path))
    }
}
