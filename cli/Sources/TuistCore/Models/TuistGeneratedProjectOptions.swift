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
                testInsightsDisabled: true,
                disableSandbox: true,
                includeGenerateScheme: false,
                enableCaching: false
            ),
            installOptions: .init(passthroughSwiftPackageManagerArguments: []),
            cacheOptions: CacheOptions(keepSourceTargets: false, profiles: .init([:], default: .onlyExternal))
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

        @available(*, deprecated, message: "Use `additionalPackageResolutionArguments` instead.")
        public let resolveDependenciesWithSystemScm: Bool
        public let disablePackageVersionLocking: Bool
        @available(*, deprecated, message: "Use `additionalPackageResolutionArguments` instead.")
        public let clonedSourcePackagesDirPath: AbsolutePath?
        public var additionalPackageResolutionArguments: [String]
        public let staticSideEffectsWarningTargets: StaticSideEffectsWarningTargets
        public let enforceExplicitDependencies: Bool
        public let defaultConfiguration: String?
        public var optionalAuthentication: Bool
        public let buildInsightsDisabled: Bool
        public let testInsightsDisabled: Bool
        public let disableSandbox: Bool
        public let includeGenerateScheme: Bool
        public let enableCaching: Bool

        public init(
            resolveDependenciesWithSystemScm: Bool,
            disablePackageVersionLocking: Bool,
            clonedSourcePackagesDirPath: AbsolutePath? = nil,
            additionalPackageResolutionArguments: [String] = [],
            staticSideEffectsWarningTargets: StaticSideEffectsWarningTargets = .all,
            enforceExplicitDependencies: Bool = false,
            defaultConfiguration: String? = nil,
            optionalAuthentication: Bool = false,
            buildInsightsDisabled: Bool,
            testInsightsDisabled: Bool,
            disableSandbox: Bool,
            includeGenerateScheme: Bool,
            enableCaching: Bool = false
        ) {
            self.resolveDependenciesWithSystemScm = resolveDependenciesWithSystemScm
            self.disablePackageVersionLocking = disablePackageVersionLocking
            self.clonedSourcePackagesDirPath = clonedSourcePackagesDirPath
            self.additionalPackageResolutionArguments = additionalPackageResolutionArguments
            self.staticSideEffectsWarningTargets = staticSideEffectsWarningTargets
            self.enforceExplicitDependencies = enforceExplicitDependencies
            self.defaultConfiguration = defaultConfiguration
            self.optionalAuthentication = optionalAuthentication
            self.buildInsightsDisabled = buildInsightsDisabled
            self.testInsightsDisabled = testInsightsDisabled
            self.disableSandbox = disableSandbox
            self.includeGenerateScheme = includeGenerateScheme
            self.enableCaching = enableCaching
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
    extension TuistGeneratedProjectOptions.GenerationOptions {
        public func withWorkspaceName(_ workspaceName: String) -> Self {
            var options = self
            if let clonedSourcePackagesDirPath {
                var workspaceName = workspaceName
                if workspaceName.hasSuffix(".xcworkspace") {
                    workspaceName = String(workspaceName.dropLast(".xcworkspace".count))
                }
                let mangledWorkspaceName = workspaceName.spm_mangledToC99ExtendedIdentifier()
                var additionalPackageResolutionArguments = options.additionalPackageResolutionArguments
                additionalPackageResolutionArguments.append(
                    contentsOf: [
                        "-clonedSourcePackagesDirPath",
                        clonedSourcePackagesDirPath.appending(component: mangledWorkspaceName).pathString,
                    ]
                )
                options.additionalPackageResolutionArguments = additionalPackageResolutionArguments
            }
            return options
        }
    }

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
            additionalPackageResolutionArguments: [String] = [],
            staticSideEffectsWarningTargets: TuistGeneratedProjectOptions.GenerationOptions
                .StaticSideEffectsWarningTargets = .all,
            enforceExplicitDependencies: Bool = false,
            defaultConfiguration: String? = nil,
            optionalAuthentication: Bool = false,
            buildInsightsDisabled: Bool = true,
            testInsightsDisabled: Bool = true,
            disableSandbox: Bool = true,
            includeGenerateScheme: Bool = true,
            enableCaching: Bool = false
        ) -> Self {
            .init(
                resolveDependenciesWithSystemScm: resolveDependenciesWithSystemScm,
                disablePackageVersionLocking: disablePackageVersionLocking,
                clonedSourcePackagesDirPath: clonedSourcePackagesDirPath,
                additionalPackageResolutionArguments: additionalPackageResolutionArguments,
                staticSideEffectsWarningTargets: staticSideEffectsWarningTargets,
                enforceExplicitDependencies: enforceExplicitDependencies,
                defaultConfiguration: defaultConfiguration,
                optionalAuthentication: optionalAuthentication,
                buildInsightsDisabled: buildInsightsDisabled,
                testInsightsDisabled: testInsightsDisabled,
                disableSandbox: disableSandbox,
                includeGenerateScheme: includeGenerateScheme,
                enableCaching: enableCaching
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
