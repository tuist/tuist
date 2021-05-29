import Foundation
import TSCBasic

/// A `Plugin` used to extend Tuist.
public struct Plugin: Equatable, Hashable {
    /// The name of the plugin.
    public let name: String

    /// Creates a `Plugin`
    ///
    /// - Parameters:
    ///     - name: The name of the plugin.
    public init(name: String) {
        self.name = name
    }
}

extension Plugin: CustomStringConvertible {
    public var description: String {
        "Plugin: \(name)"
    }
}
