import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistLoader
import TuistSupport

/// A protocol defining a service for interacting with plugins.
public protocol PluginServicing {
    /// Loads the `Plugins` and returns them as defined in given config.
    /// - Throws: An error if there are issues fetching or loading a plugin.
    /// - Returns: The loaded `Plugins` representation.
    func loadPlugins(using config: Config) throws -> Plugins
}
