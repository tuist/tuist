extension Tuist {
    /// Options for project generation.
    public struct GenerationOptions: Codable, Equatable, Sendable {
        /// This enum represents the targets against which Tuist will run the check for potential side effects
        /// caused by static transitive dependencies.
        public enum StaticSideEffectsWarningTargets: Codable, Equatable, Sendable {
            case all
            case none
            case excluding([String])
        }

        /// Categories of warnings that can be promoted to errors.
        public enum GenerationWarning: String, Codable, Equatable, Hashable, Sendable {
            case outdatedDependencies
            case staticSideEffects
            case schemeTargetNotFound
            case mismatchedConfigurations
            case duplicateProductNames
        }

        /// Controls which generation warnings are promoted to errors.
        public enum WarningsAsErrors: Codable, Equatable, Sendable {
            /// No warnings are promoted to errors (default behavior).
            case none
            /// All warnings are promoted to errors.
            case all
            /// Only the specified warning categories are promoted to errors.
            case only([GenerationWarning])
        }

        /// How `tuist generate` reacts when it detects that dependencies are outdated
        /// (i.e. `Package.resolved` has changed since the last `tuist install`).
        public enum OutdatedDependenciesAction: String, Codable, Equatable, Sendable {
            /// Print a warning and continue generation (default).
            case warn
            /// Run `tuist install` automatically and then continue generation.
            case install
            /// Fail generation, requiring the user to run `tuist install` first.
            case fail
        }

        /// The on-disk format used to serialize each generated `.xcodeproj`.
        public enum ProjectFormat: String, Codable, Equatable, Sendable {
            /// The classic OpenStep property list format stored in `project.pbxproj`.
            case pbxproj
            /// The experimental JSON5 format introduced in Xcode 27.2, stored in `project.xcproj`.
            /// Requires Xcode 27.2 or later to open the generated projects.
            case xcproj
        }

        /// This is now deprecated.
        ///
        /// To achieve the same behaviour, use `additionalPackageResolutionArguments` like so:
        ///
        /// ```swift
        /// .options(
        ///     additionalPackageResolutionArguments: ["-scmProvider", "system"]
        /// )
        /// ```
        @available(*, deprecated, message: "Use `additionalPackageResolutionArguments` instead.")
        public var resolveDependenciesWithSystemScm: Bool

        /// Disables locking Swift packages. This can speed up generation but does increase risk if packages are not locked
        /// in their declarations.
        public var disablePackageVersionLocking: Bool

        /// This is now deprecated.
        ///
        /// To achieve the same behaviour, use `additionalPackageResolutionArguments` like so:
        ///
        /// ```swift
        /// .options(
        ///     additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", "/path/to/dir/MyWorkspace"]
        /// )
        /// ```
        ///
        /// Note that `/path/to/dir` is the path you would have passed to `clonedSourcePackagesDirPath`,
        /// and `MyWorkspace` is the name of your workspace.
        @available(*, deprecated, message: "Use `additionalPackageResolutionArguments` instead.")
        public var clonedSourcePackagesDirPath: Path?

        /// A list of arguments to be passed to `xcodebuild` when resolving package dependencies.
        public var additionalPackageResolutionArguments: [String]

        /// Allows configuring which targets Tuist checks for potential side effects due multiple branches of the graph
        /// including the same static library of framework as a transitive dependency.
        public var staticSideEffectsWarningTargets: StaticSideEffectsWarningTargets

        /// The generated project has build settings and build paths modified in such a way that projects with implicit
        /// dependencies won't build until all dependencies are declared explicitly.
        public let enforceExplicitDependencies: Bool

        /// The default configuration to be used when generating the project.
        /// If not specified, Tuist generates for the first (when alphabetically sorted) debug configuration.
        public var defaultConfiguration: String?

        /// Marks whether the Tuist server authentication is optional.
        /// If present, the interaction with the Tuist server will be skipped (instead of failing) if a user is not authenticated.
        public var optionalAuthentication: Bool

        /// When disabled, build insights are not collected. Build insights are never collected unless you are connected to a
        /// remote Tuist project.
        public var buildInsightsDisabled: Bool

        /// When disabled, test insights are not collected. Test insights are never collected unless you are connected to a
        /// remote Tuist project.
        public var testInsightsDisabled: Bool

        /// Disables building manifests in a sandboxed environment. This option is currently opt-in.
        ///
        /// - It is encouraged to set `disableSandbox` to `false` (and thus to enable it). It guards against using file system
        /// operations which:
        ///   - Make generation slow
        ///   - Cause issues with manifest caching
        public var disableSandbox: Bool

        /// When true, it includes a scheme to run "tuist generate"
        public var includeGenerateScheme: Bool

        /// When enabled, adds Xcode compilation-cache settings and configures LLDB source mappings
        /// for the workspace's Run and Test actions, including automatically generated schemes.
        /// Projects can disable `SWIFT_ENABLE_PROJECT_PREFIX_MAPPING` and `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`
        /// in their manifest settings to keep sources from different projects in the shared repository
        /// namespace instead of `/^src`. Per-project mapping remains enabled by default.
        public var enableCaching: Bool

        /// Controls whether Tuist adds compilation-cache prefix mappings on Xcode 27 and later.
        /// Defaults to `true` and requires `enableCaching`. Set to `false` to keep unmapped source paths
        /// when CI uses compilation caching but local builds do not. Compilation-cache keys then depend
        /// on checkout and build-directory paths. Explicit mappings in project settings are preserved.
        public var enableCachingPrefixMapping: Bool

        /// Keeps compilation-cache prefix mapping enabled for coverage builds on Xcode 27 and later.
        /// Defaults to `false` because `xccov` cannot resolve the mapped source paths.
        /// Enable only when reading coverage with a tool such as `llvm-cov` and remapping paths using
        /// each binary's target-specific `compilation-prefix-map.json`.
        /// Requires both `enableCaching` and `enableCachingPrefixMapping`.
        public var enableCoveragePrefixMapping: Bool

        /// When enabled, generates the Swift Package Registry configuration file during project generation.
        /// This eliminates the need to run `tuist registry setup` separately.
        public var registryEnabled: Bool

        /// Controls which generation warnings are promoted to errors, causing `tuist generate` to fail.
        public var warningsAsErrors: WarningsAsErrors

        /// The default Swift language mode (`SWIFT_VERSION` build setting) applied to local targets
        /// that don't specify one. This controls which Swift language mode the compiler uses
        /// (e.g. `"5"` for Swift 5 mode, `"6"` for Swift 6 strict concurrency mode).
        /// External SPM packages are not affected — their language mode is derived from their
        /// own `Package.swift` manifest, matching SPM's behavior.
        public var defaultSwiftVersion: String

        /// Names of process environment variables that Tuist forwards to manifest evaluation
        /// in addition to the default set (`TUIST_*`, `CI`, and `DEVELOPER_DIR`).
        ///
        /// Each entry is either a literal name (e.g. `OPENSWIFTUI_LIBRARY_TYPE`) or a name
        /// ending in `*` for prefix matching (e.g. `OPENSWIFTUI_*`).
        ///
        /// Listed variables also participate in the manifest cache hash, so changes invalidate
        /// the cache as expected.
        public var manifestEnvironment: [String]

        /// Controls how `tuist generate` reacts to outdated dependencies. Defaults to `.warn`.
        public var onOutdatedDependencies: OutdatedDependenciesAction

        /// The on-disk format used to serialize each generated `.xcodeproj`. Defaults to `.pbxproj`.
        /// Set to `.xcproj` to opt into Xcode 27.2's experimental JSON5 project format.
        public var projectFormat: ProjectFormat

        public static func options(
            disablePackageVersionLocking: Bool = false,
            staticSideEffectsWarningTargets: StaticSideEffectsWarningTargets = .all,
            defaultConfiguration: String? = nil,
            optionalAuthentication: Bool = false,
            buildInsightsDisabled: Bool = false,
            testInsightsDisabled: Bool = false,
            disableSandbox: Bool = true,
            includeGenerateScheme: Bool = true,
            enableCaching: Bool = false,
            enableCoveragePrefixMapping: Bool = false,
            registryEnabled: Bool = false,
            additionalPackageResolutionArguments: [String] = [],
            warningsAsErrors: WarningsAsErrors = .none,
            defaultSwiftVersion: String = "5",
            manifestEnvironment: [String] = [],
            onOutdatedDependencies: OutdatedDependenciesAction = .warn,
            projectFormat: ProjectFormat = .pbxproj
        ) -> Self {
            options(
                disablePackageVersionLocking: disablePackageVersionLocking,
                staticSideEffectsWarningTargets: staticSideEffectsWarningTargets,
                defaultConfiguration: defaultConfiguration,
                optionalAuthentication: optionalAuthentication,
                buildInsightsDisabled: buildInsightsDisabled,
                testInsightsDisabled: testInsightsDisabled,
                disableSandbox: disableSandbox,
                includeGenerateScheme: includeGenerateScheme,
                enableCaching: enableCaching,
                enableCachingPrefixMapping: true,
                enableCoveragePrefixMapping: enableCoveragePrefixMapping,
                registryEnabled: registryEnabled,
                additionalPackageResolutionArguments: additionalPackageResolutionArguments,
                warningsAsErrors: warningsAsErrors,
                defaultSwiftVersion: defaultSwiftVersion,
                manifestEnvironment: manifestEnvironment,
                onOutdatedDependencies: onOutdatedDependencies,
                projectFormat: projectFormat
            )
        }

        /// Creates generation options with an explicit compilation-cache prefix-mapping policy.
        @_disfavoredOverload
        public static func options(
            disablePackageVersionLocking: Bool = false,
            staticSideEffectsWarningTargets: StaticSideEffectsWarningTargets = .all,
            defaultConfiguration: String? = nil,
            optionalAuthentication: Bool = false,
            buildInsightsDisabled: Bool = false,
            testInsightsDisabled: Bool = false,
            disableSandbox: Bool = true,
            includeGenerateScheme: Bool = true,
            enableCaching: Bool = false,
            enableCachingPrefixMapping: Bool,
            enableCoveragePrefixMapping: Bool = false,
            registryEnabled: Bool = false,
            additionalPackageResolutionArguments: [String] = [],
            warningsAsErrors: WarningsAsErrors = .none,
            defaultSwiftVersion: String = "5",
            manifestEnvironment: [String] = [],
            onOutdatedDependencies: OutdatedDependenciesAction = .warn,
            projectFormat: ProjectFormat = .pbxproj
        ) -> Self {
            self.init(
                resolveDependenciesWithSystemScm: false,
                disablePackageVersionLocking: disablePackageVersionLocking,
                clonedSourcePackagesDirPath: nil,
                additionalPackageResolutionArguments: additionalPackageResolutionArguments,
                staticSideEffectsWarningTargets: staticSideEffectsWarningTargets,
                enforceExplicitDependencies: false,
                defaultConfiguration: defaultConfiguration,
                optionalAuthentication: optionalAuthentication,
                buildInsightsDisabled: buildInsightsDisabled,
                testInsightsDisabled: testInsightsDisabled,
                disableSandbox: disableSandbox,
                includeGenerateScheme: includeGenerateScheme,
                enableCaching: enableCaching,
                enableCachingPrefixMapping: enableCachingPrefixMapping,
                enableCoveragePrefixMapping: enableCoveragePrefixMapping,
                registryEnabled: registryEnabled,
                warningsAsErrors: warningsAsErrors,
                defaultSwiftVersion: defaultSwiftVersion,
                manifestEnvironment: manifestEnvironment,
                onOutdatedDependencies: onOutdatedDependencies,
                projectFormat: projectFormat
            )
        }

        @_disfavoredOverload
        @available(
            *,
            deprecated,
            message: "Use `options(disablePackageVersionLocking:staticSideEffectsWarningTargets:defaultConfiguration:optionalAuthentication:buildInsightsDisabled:testInsightsDisabled:disableSandbox:includeGenerateScheme:additionalPackageResolutionArguments)` instead."
        )
        public static func options(
            resolveDependenciesWithSystemScm: Bool = false,
            disablePackageVersionLocking: Bool = false,
            clonedSourcePackagesDirPath: Path? = nil,
            staticSideEffectsWarningTargets: StaticSideEffectsWarningTargets = .all,
            defaultConfiguration: String? = nil,
            optionalAuthentication: Bool = false,
            buildInsightsDisabled: Bool = false,
            testInsightsDisabled: Bool = false,
            disableSandbox: Bool = true,
            includeGenerateScheme: Bool = true,
            enableCaching: Bool = false
        ) -> Self {
            self.init(
                resolveDependenciesWithSystemScm: resolveDependenciesWithSystemScm,
                disablePackageVersionLocking: disablePackageVersionLocking,
                clonedSourcePackagesDirPath: clonedSourcePackagesDirPath,
                additionalPackageResolutionArguments: [],
                staticSideEffectsWarningTargets: staticSideEffectsWarningTargets,
                enforceExplicitDependencies: false,
                defaultConfiguration: defaultConfiguration,
                optionalAuthentication: optionalAuthentication,
                buildInsightsDisabled: buildInsightsDisabled,
                testInsightsDisabled: testInsightsDisabled,
                disableSandbox: disableSandbox,
                includeGenerateScheme: includeGenerateScheme,
                enableCaching: enableCaching,
                enableCachingPrefixMapping: true,
                enableCoveragePrefixMapping: false,
                registryEnabled: false,
                warningsAsErrors: .none,
                defaultSwiftVersion: "5",
                manifestEnvironment: [],
                onOutdatedDependencies: .warn,
                projectFormat: .pbxproj
            )
        }

        @available(
            *,
            deprecated,
            message: "enforceExplicitDependencies is deprecated. Use 'tuist inspect dependencies --only implicit' instead."
        )
        public static func options(
            resolveDependenciesWithSystemScm: Bool = false,
            disablePackageVersionLocking: Bool = false,
            clonedSourcePackagesDirPath: Path? = nil,
            staticSideEffectsWarningTargets: StaticSideEffectsWarningTargets = .all,
            enforceExplicitDependencies: Bool,
            defaultConfiguration: String? = nil,
            optionalAuthentication: Bool = false
        ) -> Self {
            self.init(
                resolveDependenciesWithSystemScm: resolveDependenciesWithSystemScm,
                disablePackageVersionLocking: disablePackageVersionLocking,
                clonedSourcePackagesDirPath: clonedSourcePackagesDirPath,
                additionalPackageResolutionArguments: [],
                staticSideEffectsWarningTargets: staticSideEffectsWarningTargets,
                enforceExplicitDependencies: enforceExplicitDependencies,
                defaultConfiguration: defaultConfiguration,
                optionalAuthentication: optionalAuthentication,
                buildInsightsDisabled: false,
                testInsightsDisabled: false,
                disableSandbox: true,
                includeGenerateScheme: false,
                enableCaching: false,
                enableCachingPrefixMapping: true,
                enableCoveragePrefixMapping: false,
                registryEnabled: false,
                warningsAsErrors: .none,
                defaultSwiftVersion: "5",
                manifestEnvironment: [],
                onOutdatedDependencies: .warn,
                projectFormat: .pbxproj
            )
        }
    }
}

extension Tuist.GenerationOptions {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            resolveDependenciesWithSystemScm: try container.decode(Bool.self, forKey: .resolveDependenciesWithSystemScm),
            disablePackageVersionLocking: try container.decode(Bool.self, forKey: .disablePackageVersionLocking),
            clonedSourcePackagesDirPath: try container.decodeIfPresent(Path.self, forKey: .clonedSourcePackagesDirPath),
            additionalPackageResolutionArguments: try container.decode(
                [String].self,
                forKey: .additionalPackageResolutionArguments
            ),
            staticSideEffectsWarningTargets: try container.decode(
                StaticSideEffectsWarningTargets.self,
                forKey: .staticSideEffectsWarningTargets
            ),
            enforceExplicitDependencies: try container.decode(Bool.self, forKey: .enforceExplicitDependencies),
            defaultConfiguration: try container.decodeIfPresent(String.self, forKey: .defaultConfiguration),
            optionalAuthentication: try container.decode(Bool.self, forKey: .optionalAuthentication),
            buildInsightsDisabled: try container.decode(Bool.self, forKey: .buildInsightsDisabled),
            testInsightsDisabled: try container.decode(Bool.self, forKey: .testInsightsDisabled),
            disableSandbox: try container.decode(Bool.self, forKey: .disableSandbox),
            includeGenerateScheme: try container.decode(Bool.self, forKey: .includeGenerateScheme),
            enableCaching: try container.decode(Bool.self, forKey: .enableCaching),
            enableCachingPrefixMapping: try container.decodeIfPresent(Bool.self, forKey: .enableCachingPrefixMapping) ?? true,
            enableCoveragePrefixMapping: try container.decode(Bool.self, forKey: .enableCoveragePrefixMapping),
            registryEnabled: try container.decode(Bool.self, forKey: .registryEnabled),
            warningsAsErrors: try container.decode(WarningsAsErrors.self, forKey: .warningsAsErrors),
            defaultSwiftVersion: try container.decode(String.self, forKey: .defaultSwiftVersion),
            manifestEnvironment: try container.decode([String].self, forKey: .manifestEnvironment),
            onOutdatedDependencies: try container.decode(OutdatedDependenciesAction.self, forKey: .onOutdatedDependencies),
            projectFormat: try container.decode(ProjectFormat.self, forKey: .projectFormat)
        )
    }
}
