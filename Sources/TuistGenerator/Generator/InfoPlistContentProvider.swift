import Foundation

/// Defines the interface to obtain the content to generate derived Info.plist files for the targets.
protocol InfoPlistContentProviding {
    /// It returns the content that should be used to generate an Info.plist file
    /// for the given target. It uses default values that specific to the target's platform
    /// and product, and extends them with the values provided by the user.
    ///
    /// - Parameters:
    ///   - target: Target whose Info.plist content will be returned.
    ///   - extendedWith: Values provided by the user to extend the default ones.
    /// - Returns: Content to generate the Info.plist file.
    func content(target: Target, extendedWith: [String: InfoPlist.Value]) -> [String: Any]
}

final class InfoPlistContentProvider: InfoPlistContentProviding {
    /// It returns the content that should be used to generate an Info.plist file
    /// for the given target. It uses default values that specific to the target's platform
    /// and product, and extends them with the values provided by the user.
    ///
    /// - Parameters:
    ///   - target: Target whose Info.plist content will be returned.
    ///   - extendedWith: Values provided by the user to extend the default ones.
    /// - Returns: Content to generate the Info.plist file.
    func content(target _: Target, extendedWith _: [String: InfoPlist.Value]) -> [String: Any] {
        // TODO:
        return [:]
    }
}
