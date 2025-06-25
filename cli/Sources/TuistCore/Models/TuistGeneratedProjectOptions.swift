import Path
import XcodeGraph

public struct TuistGeneratedProjectOptions: Equatable, Hashable {
    public let compatibleXcodeVersions: CompatibleXcodeVersions
    public let swiftVersion: Version?
    public let plugins: [PluginLocation]
    public let generationOptions: GenerationOptions
    public let inspectOptions: InspectOptions
    public let installOptions: InstallOptions

    public init(
        compatibleXcodeVersions: CompatibleXcodeVersions,
        swiftVersion: Version?,
        plugins: [PluginLocation],
        generationOptions: GenerationOptions,
        inspectOptions: InspectOptions,
        installOptions: InstallOptions
    ) {
        self.compatibleXcodeVersions = compatibleXcodeVersions
        self.swiftVersion = swiftVersion
        self.plugins = plugins
        self.generationOptions = generationOptions
        self.inspectOptions = inspectOptions
        self.installOptions = installOptions
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(compatibleXcodeVersions)
        hasher.combine(swiftVersion)
        hasher.combine(plugins)
        hasher.combine(generationOptions)
        hasher.combine(inspectOptions)
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
                staticSideEffectsWarningTargets: .all,
                buildInsightsDisabled: true,
                disableSandbox: false
            ),
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            installOptions: .init(passthroughSwiftPackageManagerArguments: [])
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

        public init(
            resolveDependenciesWithSystemScm: Bool,
            disablePackageVersionLocking: Bool,
            clonedSourcePackagesDirPath: AbsolutePath? = nil,
            staticSideEffectsWarningTargets: StaticSideEffectsWarningTargets = .all,
            enforceExplicitDependencies: Bool = false,
            defaultConfiguration: String? = nil,
            optionalAuthentication: Bool = false,
            buildInsightsDisabled: Bool,
            disableSandbox: Bool
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
        }
    }

    public struct InspectOptions: Codable, Equatable, Hashable, Sendable {
        public struct RedundantDependencies: Codable, Equatable, Hashable, Sendable {
            public let ignoreTagsMatching: Set<String>

            public init(
                ignoreTagsMatching: Set<String>
            ) {
                self.ignoreTagsMatching = ignoreTagsMatching
            }
        }

        public var redundantDependencies: RedundantDependencies

        public init(
            redundantDependencies: RedundantDependencies
        ) {
            self.redundantDependencies = redundantDependencies
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
            inspectOptions: InspectOptions = .test(),
            installOptions: InstallOptions = .test()
        ) -> Self {
            return .init(
                compatibleXcodeVersions: compatibleXcodeVersions,
                swiftVersion: swiftVersion,
                plugins: plugins,
                generationOptions: generationOptions,
                inspectOptions: inspectOptions,
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
            optionalAuthentication: Bool = false,
            buildInsightsDisabled: Bool = true,
            disableSandbox: Bool = false
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
                disableSandbox: disableSandbox
            )
        }
    }

    extension TuistGeneratedProjectOptions.InspectOptions {
        public static func test(
            redundantDependencies: RedundantDependencies = .init(ignoreTagsMatching: [])
        ) -> Self {
            .init(
                redundantDependencies: redundantDependencies
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
