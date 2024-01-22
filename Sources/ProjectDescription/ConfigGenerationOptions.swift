extension Config {
    /// Options for project generation.
    public struct GenerationOptions: Codable, Equatable {
        /**
         This enum represents the targets against which Tuist will run the check for potential side effects
         caused by static transitive dependencies.
         */
        public enum StaticSideEffectsWarningTargets: Codable, Equatable {
            case all
            case none
            case excluding([String])
        }

        /// When passed, Xcode will resolve its Package Manager dependencies using the system-defined
        /// accounts (for example, git) instead of the Xcode-defined accounts
        public var resolveDependenciesWithSystemScm: Bool = false

        /// Disables locking Swift packages. This can speed up generation but does increase risk if packages are not locked
        /// in their declarations.
        public var disablePackageVersionLocking: Bool = false

        /// Allows setting a custom directory to be used when resolving package dependencies
        /// This path is passed to `xcodebuild` via the `-clonedSourcePackagesDirPath` argument
        public var clonedSourcePackagesDirPath: Path? = nil

        /// Allows configuring which targets Tuist checks for potential side effects due multiple branches of the graph
        /// including the same static library of framework as a transitive dependency.
        public var staticSideEffectsWarningTargets: StaticSideEffectsWarningTargets = .all

        /// The generated project has build settings and build paths modified in such a way that projects with implicit
        /// dependencies won't build until all dependencies are declared explicitly.
        public let enforceExplicitDependencies: Bool = false
    }
}
