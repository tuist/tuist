import Foundation
import TSCBasic
import TSCUtility

/// This model allows to configure Tuist.
public struct Config: Equatable, Hashable {
    /// List of `Plugin`s used to extend Tuist.
    public let plugins: [PluginLocation]

    /// Generation options.
    public let generationOptions: GenerationOptions

    /// List of Xcode versions the project or set of projects is compatible with.
    public let compatibleXcodeVersions: CompatibleXcodeVersions

    /// Cloud configuration.
    public let cloud: Cloud?

    /// Cache configuration.
    public let cache: Cache?

    /// The version of Swift that will be used by Tuist.
    /// If `nil` is passed then Tuist will use the environment’s version.
    public let swiftVersion: Version?

    /// The path of the config file.
    public let path: AbsolutePath?

    /// Returns the default Tuist configuration.
    public static var `default`: Config {
        Config(
            compatibleXcodeVersions: .all,
            cloud: nil,
            cache: nil,
            swiftVersion: nil,
            plugins: [],
            generationOptions: .init(
                resolveDependenciesWithSystemScm: false,
                disablePackageVersionLocking: false
            ),
            path: nil
        )
    }

    /// Initializes the tuist cofiguration.
    ///
    /// - Parameters:
    ///   - compatibleXcodeVersions: List of Xcode versions the project or set of projects is compatible with.
    ///   - cloud: Cloud configuration.
    ///   - cache: Cache configuration.
    ///   - swiftVersion: The version of Swift that will be used by Tuist.
    ///   - plugins: List of locations to a `Plugin` manifest.
    ///   - generationOptions: Generation options.
    ///   - path: The path of the config file.
    public init(
        compatibleXcodeVersions: CompatibleXcodeVersions,
        cloud: Cloud?,
        cache: Cache?,
        swiftVersion: Version?,
        plugins: [PluginLocation],
        generationOptions: GenerationOptions,
        path: AbsolutePath?
    ) {
        self.compatibleXcodeVersions = compatibleXcodeVersions
        self.cloud = cloud
        self.cache = cache
        self.swiftVersion = swiftVersion
        self.plugins = plugins
        self.generationOptions = generationOptions
        self.path = path
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(generationOptions)
        hasher.combine(cloud)
        hasher.combine(cache)
        hasher.combine(swiftVersion)
        hasher.combine(compatibleXcodeVersions)
    }
}
