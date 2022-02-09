import TSCUtility

extension Config {
    /// Contains options related to the project generation.
    public struct GenerationOptions: Codable, Hashable {
        /// Tuist generates the project with the specific name on disk instead of using the project name.
        public let xcodeProjectName: String?

        /// Tuist generates the project with the specific organization name.
        public let organizationName: String?

        /// Tuist generates the project with the specific development region.
        public let developmentRegion: String?

        /// When passed, Xcode will resolve its Package Manager dependencies using the system-defined
        /// accounts (for example, git) instead of the Xcode-defined accounts
        public let resolveDependenciesWithSystemScm: Bool

        /// IDE template macros
        public let templateMacros: IDETemplateMacros?

        /// Disables locking Swift packages. This can speed up generation but does increase risk if packages are not locked
        /// in their declarations.
        public let disablePackageVersionLocking: Bool

        public init(
            xcodeProjectName: String?,
            organizationName: String?,
            developmentRegion: String?,
            templateMacros: IDETemplateMacros?,
            resolveDependenciesWithSystemScm: Bool,
            disablePackageVersionLocking: Bool
        ) {
            self.xcodeProjectName = xcodeProjectName
            self.organizationName = organizationName
            self.developmentRegion = developmentRegion
            self.templateMacros = templateMacros
            self.resolveDependenciesWithSystemScm = resolveDependenciesWithSystemScm
            self.disablePackageVersionLocking = disablePackageVersionLocking
        }
    }
}
