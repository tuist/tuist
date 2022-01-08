import Foundation
import TSCBasic
import TSCUtility

/// This model allows to configure Tuist.
public struct Config: Equatable, Hashable {
    /// Contains options related to the project generation.
    public enum GenerationOption: Hashable, Equatable {
        /// Name used for the Xcode project
        case xcodeProjectName(String)
        case organizationName(String)
        case developmentRegion(String)
        case autogenerationOptions(AutogenerationOptions)
        case disableShowEnvironmentVarsInScriptPhases
        case enableCodeCoverage(CodeCoverageMode)
        case templateMacros(IDETemplateMacros)
        case resolveDependenciesWithSystemScm
        /// Disables locking Swift packages. This can speed up generation but does increase risk if packages are not locked
        /// in their declarations.
        case disablePackageVersionLocking
        /// Allows to suppress warnings in Xcode about updates to recommended settings.
        case lastUpgradeCheck(Version)
    }

    /// List of `Plugin`s used to extend Tuist.
    public let plugins: [PluginLocation]

    /// Generation options.
    public let generationOptions: [GenerationOption]

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
            generationOptions: [],
            path: nil
        )
    }

    public var codeCoverageMode: CodeCoverageMode? {
        generationOptions.compactMap { option -> CodeCoverageMode? in
            switch option {
            case let .enableCodeCoverage(mode): return mode
            default: return nil
            }
        }.first
    }

    public var autogenerationTestingOptions: AutogenerationOptions.TestingOptions? {
        let autogenerationOptions = generationOptions.compactMap { option -> AutogenerationOptions? in
            switch option {
            case let .autogenerationOptions(options): return options
            default: return nil
            }
        }.first

        switch autogenerationOptions {
        case let .enabled(options):
            return options
        case .disabled:
            return nil
        case nil:
            // no value provided is equivalent to .enabled([])
            return []
        }
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
        generationOptions: [GenerationOption],
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
