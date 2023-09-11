extension Config {
    /// Options for project generation.
    public struct GenerationOptions: Codable, Equatable {
        /// When passed, Xcode will resolve its Package Manager dependencies using the system-defined
        /// accounts (for example, git) instead of the Xcode-defined accounts
        public let resolveDependenciesWithSystemScm: Bool

        /// Disables locking Swift packages. This can speed up generation but does increase risk if packages are not locked
        /// in their declarations.
        public let disablePackageVersionLocking: Bool

        /// Allows setting a custom directory to be used when resolving package dependencies
        /// This path is passed to `xcodebuild` via the `-clonedSourcePackagesDirPath` argument
        public let clonedSourcePackagesDirPath: Path?

        public static func options(
            resolveDependenciesWithSystemScm: Bool = false,
            disablePackageVersionLocking: Bool = false,
            clonedSourcePackagesDirPath: Path? = nil
        ) -> Self {
            self.init(
                resolveDependenciesWithSystemScm: resolveDependenciesWithSystemScm,
                disablePackageVersionLocking: disablePackageVersionLocking,
                clonedSourcePackagesDirPath: clonedSourcePackagesDirPath
            )
        }
    }
}
