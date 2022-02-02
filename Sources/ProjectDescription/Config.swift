import Foundation

/// This model allows to configure Tuist.
public struct Config: Codable, Equatable {
    /// Contains options related to the project generation.
    public enum GenerationOptions: Codable, Equatable {
        /// Tuist generates the project with the specific name on disk instead of using the project name.
        case xcodeProjectName(TemplateString)

        /// Tuist generates the project with the specific organization name.
        case organizationName(String)

        /// Tuist generates the project with the specific development region.
        case developmentRegion(String)

        /// Tuist disables echoing the ENV in shell script build phases
        case disableShowEnvironmentVarsInScriptPhases

        /// When passed, Xcode will resolve its Package Manager dependencies using the system-defined
        /// accounts (e.g. git) instead of the Xcode-defined accounts
        case resolveDependenciesWithSystemScm

        /// Disables locking Swift packages. This can speed up generation but does increase risk if packages are not locked
        /// in their declarations.
        case disablePackageVersionLocking

        /// Allows to suppress warnings in Xcode about updates to recommended settings added in or below the specified Xcode version. The warnings appear when Xcode version has been upgraded.
        /// It is recommended to set the version option to Xcode's version that is used for development of a project, for example `.lastUpgradeCheck(Version(13, 0, 0))` for Xcode 13.0.0.
        case lastXcodeUpgradeCheck(Version)
    }

    /// Generation options.
    public let generationOptions: [GenerationOptions]

    /// List of Xcode versions that the project supports.
    public let compatibleXcodeVersions: CompatibleXcodeVersions

    /// List of `Plugin`s used to extend Tuist.
    public let plugins: [PluginLocation]

    /// Cloud configuration.
    public let cloud: Cloud?

    /// Cache configuration.
    public let cache: Cache?

    /// The version of Swift that will be used by Tuist.
    /// If `nil` is passed then Tuist will use the environment’s version.
    public let swiftVersion: Version?

    /// Initializes the tuist configuration.
    ///
    /// - Parameters:
    ///   - compatibleXcodeVersions: List of Xcode versions the project is compatible with.
    ///   - cloud: Cloud configuration.
    ///   - cache: Cache configuration.
    ///   - swiftVersion: The version of Swift that will be used by Tuist.
    ///   - plugins: A list of plugins to extend Tuist.
    ///   - generationOptions: List of options to use when generating the project.
    public init(
        compatibleXcodeVersions: CompatibleXcodeVersions = .all,
        cloud: Cloud? = nil,
        cache: Cache? = nil,
        swiftVersion: Version? = nil,
        plugins: [PluginLocation] = [],
        generationOptions: [GenerationOptions]
    ) {
        self.compatibleXcodeVersions = compatibleXcodeVersions
        self.plugins = plugins
        self.generationOptions = generationOptions
        self.cloud = cloud
        self.cache = cache
        self.swiftVersion = swiftVersion
        dumpIfNeeded(self)
    }
}
