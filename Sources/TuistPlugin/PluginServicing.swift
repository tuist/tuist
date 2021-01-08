import Foundation
import TSCBasic
import TuistCore
import TuistLoader
import TuistSupport

/// A protocol defining a service for interacting with plugins.
public protocol PluginServicing {
    /// Loads the `Plugins` and returns them as defined in given config.
    /// Attempts to first locate and load the `Config` manifest.
    /// The given path must be a valid location where a `Config` manifest may be found.
    /// - Throws: An error if couldn't load a plugin.
    /// - Returns: The loaded `Plugins` representation.
    func loadPlugins(at path: AbsolutePath) throws -> Plugins

    /// Loads the `Plugins` and returns them as defined in given config.
    /// - Throws: An error if couldn't load a plugin.
    /// - Returns: The loaded `Plugins` representation.
    func loadPlugins(using config: Config) throws -> Plugins
}
