import Path
import XcodeGraph

public struct TuistGeneratedProjectOptions: Equatable, Hashable {
    public let compatibleXcodeVersions: CompatibleXcodeVersions
    public let swiftVersion: Version?
    public let plugins: [PluginLocation]
    public let generationOptions: GenerationOptions
    public let installOptions: InstallOptions
    public let cacheOptions: CacheOptions
    
    public init(
        compatibleXcodeVersions: CompatibleXcodeVersions,
        swiftVersion: Version?,
        plugins: [PluginLocation],
        generationOptions: GenerationOptions,
        installOptions: InstallOptions,
        cacheOptions: CacheOptions
    ) {
        self.compatibleXcodeVersions = compatibleXcodeVersions
        self.swiftVersion = swiftVersion
        self.plugins = plugins
        self.generationOptions = generationOptions
        self.installOptions = installOptions
        self.cacheOptions = cacheOptions
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(compatibleXcodeVersions)
        hasher.combine(swiftVersion)
        hasher.combine(plugins)
        hasher.combine(generationOptions)
        hasher.combine(installOptions)
        hasher.combine(cacheOptions)
    }

    public static var `default`: Self {
        TuistGeneratedProjectOptions(
            compatibleXcodeVersions: .all,
            swiftVersion: nil,
            plugins: [],
            generationOptions: .init(
                resolveDependenciesWithSystemScm: false,
                disablePackageVersionLocking: false,
                staticSideEffectsWarningTargets: .all,
                buildInsightsDisabled: true,
                disableSandbox: false,
                includeGenerateScheme: false
            ),
            installOptions: .init(passthroughSwiftPackageManagerArguments: []),
            cacheOptions: CacheOptions(keepSourceTargets: false)
        )
    }
}

extension TuistGeneratedProjectOptions {
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
        public let buildInsightsDisabled: Bool
        public let disableSandbox: Bool
        public let includeGenerateScheme: Bool

        public init(
            resolveDependenciesWithSystemScm: Bool,
            disablePackageVersionLocking: Bool,
            clonedSourcePackagesDirPath: AbsolutePath? = nil,
            staticSideEffectsWarningTargets: StaticSideEffectsWarningTargets = .all,
            enforceExplicitDependencies: Bool = false,
            defaultConfiguration: String? = nil,
            optionalAuthentication: Bool = false,
            buildInsightsDisabled: Bool,
            disableSandbox: Bool,
            includeGenerateScheme: Bool
        ) {
            self.resolveDependenciesWithSystemScm = resolveDependenciesWithSystemScm
            self.disablePackageVersionLocking = disablePackageVersionLocking
            self.clonedSourcePackagesDirPath = clonedSourcePackagesDirPath
            self.staticSideEffectsWarningTargets = staticSideEffectsWarningTargets
            self.enforceExplicitDependencies = enforceExplicitDependencies
            self.defaultConfiguration = defaultConfiguration
            self.optionalAuthentication = optionalAuthentication
            self.buildInsightsDisabled = buildInsightsDisabled
            self.disableSandbox = disableSandbox
            self.includeGenerateScheme = includeGenerateScheme
        }
    }
    
    public struct CacheOptions: Codable, Equatable, Sendable, Hashable {
        public var keepSourceTargets: Bool

        public init(
            keepSourceTargets: Bool = false
        ) {
            self.keepSourceTargets = keepSourceTargets
        }
    }

    public struct InstallOptions: Codable, Equatable, Sendable, Hashable {
        public var passthroughSwiftPackageManagerArguments: [String]

        public init(
            passthroughSwiftPackageManagerArguments: [String] = []
        ) {
            self.passthroughSwiftPackageManagerArguments = passthroughSwiftPackageManagerArguments
        }
    }
}

#if DEBUG
    extension TuistGeneratedProjectOptions {
        public static func test(
            compatibleXcodeVersions: CompatibleXcodeVersions = .all,
            swiftVersion: Version? = nil,
            plugins: [PluginLocation] = [],
            generationOptions: GenerationOptions = .test(),
            installOptions: InstallOptions = .test(),
            cacheOptions: CacheOptions = .test()
        ) -> Self {
            return .init(
                compatibleXcodeVersions: compatibleXcodeVersions,
                swiftVersion: swiftVersion,
                plugins: plugins,
                generationOptions: generationOptions,
                installOptions: installOptions,
                cacheOptions: cacheOptions
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
            optionalAuthentication: Bool = false,
            buildInsightsDisabled: Bool = true,
            disableSandbox: Bool = false,
            includeGenerateScheme: Bool = false
        ) -> Self {
            .init(
                resolveDependenciesWithSystemScm: resolveDependenciesWithSystemScm,
                disablePackageVersionLocking: disablePackageVersionLocking,
                clonedSourcePackagesDirPath: clonedSourcePackagesDirPath,
                staticSideEffectsWarningTargets: staticSideEffectsWarningTargets,
                enforceExplicitDependencies: enforceExplicitDependencies,
                defaultConfiguration: defaultConfiguration,
                optionalAuthentication: optionalAuthentication,
                buildInsightsDisabled: buildInsightsDisabled,
                disableSandbox: disableSandbox,
                includeGenerateScheme: includeGenerateScheme
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
extension TuistGeneratedProjectOptions.CacheOptions {
    public static func test(
        keepSourceTargets: Bool = false
    ) -> Self {
        .init(
            keepSourceTargets: keepSourceTargets
        )
    }
}


#endif
