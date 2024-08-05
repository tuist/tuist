import Foundation
import Path
import TuistSupport
import XcodeGraph

/// This model allows to configure Tuist.
public struct Config: Equatable, Hashable {
    /// List of `Plugin`s used to extend Tuist.
    public let plugins: [PluginLocation]

    /// Generation options.
    public let generationOptions: GenerationOptions

    /// List of Xcode versions the project or set of projects is compatible with.
    public let compatibleXcodeVersions: CompatibleXcodeVersions

    /// The full project handle such as tuist-org/tuist.
    public let fullHandle: String?

    /// The base URL that points to the Tuist server.
    public let url: URL

    /// The version of Swift that will be used by Tuist.
    /// If `nil` is passed then Tuist will use the environment’s version.
    public let swiftVersion: Version?

    /// The path of the config file.
    public let path: AbsolutePath?

    /// Returns the default Tuist configuration.
    public static var `default`: Config {
        Config(
            compatibleXcodeVersions: .all,
            fullHandle: nil,
            url: Constants.URLs.production,
            swiftVersion: nil,
            plugins: [],
            generationOptions: .init(
                resolveDependenciesWithSystemScm: false,
                disablePackageVersionLocking: false,
                staticSideEffectsWarningTargets: .all
            ),
            path: nil
        )
    }

    /// Initializes the tuist cofiguration.
    ///
    /// - Parameters:
    ///   - compatibleXcodeVersions: List of Xcode versions the project or set of projects is compatible with.
    ///   - cloud: Cloud configuration.
    ///   - swiftVersion: The version of Swift that will be used by Tuist.
    ///   - plugins: List of locations to a `Plugin` manifest.
    ///   - generationOptions: Generation options.
    ///   - path: The path of the config file.
    public init(
        compatibleXcodeVersions: CompatibleXcodeVersions,
        fullHandle: String?,
        url: URL,
        swiftVersion: Version?,
        plugins: [PluginLocation],
        generationOptions: GenerationOptions,
        path: AbsolutePath?
    ) {
        self.compatibleXcodeVersions = compatibleXcodeVersions
        self.fullHandle = fullHandle
        self.url = url
        self.swiftVersion = swiftVersion
        self.plugins = plugins
        self.generationOptions = generationOptions
        self.path = path
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(generationOptions)
        hasher.combine(fullHandle)
        hasher.combine(url)
        hasher.combine(swiftVersion)
        hasher.combine(compatibleXcodeVersions)
    }
}

#if DEBUG
    extension Config {
        public static func test(
            compatibleXcodeVersions: CompatibleXcodeVersions = .all,
            fullHandle: String? = nil,
            url: URL = Constants.URLs.production,
            swiftVersion: Version? = nil,
            plugins: [PluginLocation] = [],
            generationOptions: GenerationOptions = Config.default.generationOptions,
            path: AbsolutePath? = nil
        ) -> Config {
            .init(
                compatibleXcodeVersions: compatibleXcodeVersions,
                fullHandle: fullHandle,
                url: url,
                swiftVersion: swiftVersion,
                plugins: plugins,
                generationOptions: generationOptions,
                path: path
            )
        }
    }

    extension Config.GenerationOptions {
        public static func test(
            resolveDependenciesWithSystemScm: Bool = false,
            disablePackageVersionLocking: Bool = false,
            clonedSourcePackagesDirPath: AbsolutePath? = nil,
            staticSideEffectsWarningTargets: TuistCore.Config.GenerationOptions.StaticSideEffectsWarningTargets = .all,
            enforceExplicitDependencies: Bool = false,
            defaultConfiguration: String? = nil,
            optionalAuthentication: Bool = false
        ) -> Self {
            .init(
                resolveDependenciesWithSystemScm: resolveDependenciesWithSystemScm,
                disablePackageVersionLocking: disablePackageVersionLocking,
                clonedSourcePackagesDirPath: clonedSourcePackagesDirPath,
                staticSideEffectsWarningTargets: staticSideEffectsWarningTargets,
                enforceExplicitDependencies: enforceExplicitDependencies,
                defaultConfiguration: defaultConfiguration,
                optionalAuthentication: optionalAuthentication
            )
        }
    }
#endif
