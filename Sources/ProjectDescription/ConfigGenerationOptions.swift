extension Tuist {
    /// Options for project generation.
    public struct GenerationOptions: Codable, Equatable, Sendable {
        /**
         This enum represents the targets against which Tuist will run the check for potential side effects
         caused by static transitive dependencies.
         */
        public enum StaticSideEffectsWarningTargets: Codable, Equatable, Sendable {
            case all
            case none
            case excluding([String])
        }

        /// When passed, Xcode will resolve its Package Manager dependencies using the system-defined
        /// accounts (for example, git) instead of the Xcode-defined accounts
        public var resolveDependenciesWithSystemScm: Bool

        /// Disables locking Swift packages. This can speed up generation but does increase risk if packages are not locked
        /// in their declarations.
        public var disablePackageVersionLocking: Bool

        /// Allows setting a custom directory to be used when resolving package dependencies
        /// This path is passed to `xcodebuild` via the `-clonedSourcePackagesDirPath` argument
        public var clonedSourcePackagesDirPath: Path?

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

        public static func options(
            resolveDependenciesWithSystemScm: Bool = false,
            disablePackageVersionLocking: Bool = false,
            clonedSourcePackagesDirPath: Path? = nil,
            staticSideEffectsWarningTargets: StaticSideEffectsWarningTargets = .all,
            defaultConfiguration: String? = nil,
            optionalAuthentication: Bool = false
        ) -> Self {
            self.init(
                resolveDependenciesWithSystemScm: resolveDependenciesWithSystemScm,
                disablePackageVersionLocking: disablePackageVersionLocking,
                clonedSourcePackagesDirPath: clonedSourcePackagesDirPath,
                staticSideEffectsWarningTargets: staticSideEffectsWarningTargets,
                enforceExplicitDependencies: false,
                defaultConfiguration: defaultConfiguration,
                optionalAuthentication: optionalAuthentication
            )
        }

        @available(
            *,
            deprecated,
            message: "enforceExplicitDependencies is deprecated. Use the new tuist inspect implicit-imports instead."
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
                staticSideEffectsWarningTargets: staticSideEffectsWarningTargets,
                enforceExplicitDependencies: enforceExplicitDependencies,
                defaultConfiguration: defaultConfiguration,
                optionalAuthentication: optionalAuthentication
            )
        }
    }
}
