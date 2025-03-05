import Path
import XcodeGraph

public struct TuistGeneratedProjectOptions: Equatable, Hashable {
    public struct InstallOptions: Codable, Equatable, Sendable, Hashable {
        public var passthroughSwiftPackageManagerArguments: [String]

        public init(
            passthroughSwiftPackageManagerArguments: [String] = []
        ) {
            self.passthroughSwiftPackageManagerArguments = passthroughSwiftPackageManagerArguments
        }
    }

    public struct GenerationOptions: Codable, Hashable, Equatable {
        public enum StaticSideEffectsWarningTargets: Codable, Hashable, Equatable {
            case all
            case none
            case excluding([String])
        }

        public let resolveDependenciesWithSystemScm: Bool
        public let disablePackageVersionLocking: Bool
        public let clonedSourcePackagesDirPath: AbsolutePath?
        public let staticSideEffectsWarningTargets: StaticSideEffectsWarningTargets
        public let enforceExplicitDependencies: Bool
        public let defaultConfiguration: String?
        public var optionalAuthentication: Bool

        public init(
            resolveDependenciesWithSystemScm: Bool,
            disablePackageVersionLocking: Bool,
            clonedSourcePackagesDirPath: AbsolutePath? = nil,
            staticSideEffectsWarningTargets: StaticSideEffectsWarningTargets = .all,
            enforceExplicitDependencies: Bool = false,
            defaultConfiguration: String? = nil,
            optionalAuthentication: Bool = false
        ) {
            self.resolveDependenciesWithSystemScm = resolveDependenciesWithSystemScm
            self.disablePackageVersionLocking = disablePackageVersionLocking
            self.clonedSourcePackagesDirPath = clonedSourcePackagesDirPath
            self.staticSideEffectsWarningTargets = staticSideEffectsWarningTargets
            self.enforceExplicitDependencies = enforceExplicitDependencies
            self.defaultConfiguration = defaultConfiguration
            self.optionalAuthentication = optionalAuthentication
        }
    }

    public let compatibleXcodeVersions: CompatibleXcodeVersions
    public let swiftVersion: Version?
    public let plugins: [PluginLocation]
    public let generationOptions: GenerationOptions
    public let installOptions: InstallOptions

    public init(
        compatibleXcodeVersions: CompatibleXcodeVersions,
        swiftVersion: Version?,
        plugins: [PluginLocation],
        generationOptions: GenerationOptions,
        installOptions: InstallOptions
    ) {
        self.compatibleXcodeVersions = compatibleXcodeVersions
        self.swiftVersion = swiftVersion
        self.plugins = plugins
        self.generationOptions = generationOptions
        self.installOptions = installOptions
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(compatibleXcodeVersions)
        hasher.combine(swiftVersion)
        hasher.combine(plugins)
        hasher.combine(generationOptions)
        hasher.combine(installOptions)
    }

    public static var `default`: Self {
        TuistGeneratedProjectOptions(
            compatibleXcodeVersions: .all,
            swiftVersion: nil,
            plugins: [],
            generationOptions: .init(
                resolveDependenciesWithSystemScm: false,
                disablePackageVersionLocking: false,
                staticSideEffectsWarningTargets: .all
            ),
            installOptions: .init(passthroughSwiftPackageManagerArguments: [])
        )
    }
}

#if DEBUG
    extension TuistGeneratedProjectOptions {
        public static func test(
            compatibleXcodeVersions: CompatibleXcodeVersions = .all,
            swiftVersion: Version? = nil,
            plugins: [PluginLocation] = [],
            generationOptions: GenerationOptions = .test(),
            installOptions: InstallOptions = .test()
        ) -> Self {
            return .init(
                compatibleXcodeVersions: compatibleXcodeVersions,
                swiftVersion: swiftVersion,
                plugins: plugins,
                generationOptions: generationOptions,
                installOptions: installOptions
            )
        }
    }

    extension TuistGeneratedProjectOptions.GenerationOptions {
        public static func test(
            resolveDependenciesWithSystemScm: Bool = false,
            disablePackageVersionLocking: Bool = false,
            clonedSourcePackagesDirPath: AbsolutePath? = nil,
            staticSideEffectsWarningTargets: TuistGeneratedProjectOptions.GenerationOptions
                .StaticSideEffectsWarningTargets = .all,
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

    extension TuistGeneratedProjectOptions.InstallOptions {
        public static func test(
            passthroughSwiftPackageManagerArguments: [String] = []
        ) -> Self {
            .init(
                passthroughSwiftPackageManagerArguments: passthroughSwiftPackageManagerArguments
            )
        }
    }
#endif
