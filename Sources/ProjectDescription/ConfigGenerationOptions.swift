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

        public static func options(
            resolveDependenciesWithSystemScm: Bool = false,
            disablePackageVersionLocking: Bool = false,
            clonedSourcePackagesDirPath: Path? = nil,
            staticSideEffectsWarningTargets: StaticSideEffectsWarningTargets = .all
        ) -> Self {
            self.init(
                resolveDependenciesWithSystemScm: resolveDependenciesWithSystemScm,
                disablePackageVersionLocking: disablePackageVersionLocking,
                clonedSourcePackagesDirPath: clonedSourcePackagesDirPath,
                staticSideEffectsWarningTargets: staticSideEffectsWarningTargets
            )
        }
    }
}
