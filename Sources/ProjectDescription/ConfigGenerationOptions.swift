extension Config {
    /// Contains options related to the project generation.
    public struct GenerationOptions: Codable, Equatable {
        /// Tuist generates the project with the specific name on disk instead of using the project name.
        public let xcodeProjectName: TemplateString?

        /// Tuist generates the project with the specific organization name.
        public let organizationName: String?

        /// Tuist generates the project with the specific development region.
        public let developmentRegion: String?

        /// When passed, Xcode will resolve its Package Manager dependencies using the system-defined
        /// accounts (for example, git) instead of the Xcode-defined accounts
        public let resolveDependenciesWithSystemScm: Bool

        /// Disables locking Swift packages. This can speed up generation but does increase risk if packages are not locked
        /// in their declarations.
        public let disablePackageVersionLocking: Bool

        public static func options(
            xcodeProjectName: TemplateString? = nil,
            organizationName: String? = nil,
            developmentRegion: String? = nil,
            resolveDependenciesWithSystemScm: Bool = false,
            disablePackageVersionLocking: Bool = false
        ) -> Self {
            self.init(
                xcodeProjectName: xcodeProjectName,
                organizationName: organizationName,
                developmentRegion: developmentRegion,
                resolveDependenciesWithSystemScm: resolveDependenciesWithSystemScm,
                disablePackageVersionLocking: disablePackageVersionLocking
            )
        }
    }
}
