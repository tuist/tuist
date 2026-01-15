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

        /// When enabled, adds Xcode cache compilation settings to the project
        public var enableCaching: Bool

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
            additionalPackageResolutionArguments: [String] = []
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
                enableCaching: enableCaching
            )
        }

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
                enableCaching: enableCaching
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
                enableCaching: false
            )
        }
    }
}
