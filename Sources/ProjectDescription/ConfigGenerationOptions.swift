extension Config {
    /// Contains options related to the project generation.
    public struct GenerationOptions: Codable, Equatable {
        /// Tuist generates the project with the specific name on disk instead of using the project name.
        public let xcodeProjectName: TemplateString?

        /// Tuist generates the project with the specific organization name.
        public let organizationName: String?

        /// Tuist generates the project with the specific development region.
        public let developmentRegion: String?

        /// Tuist disables echoing the ENV in shell script build phases
        public let disableShowEnvironmentVarsInScriptPhases: Bool

        /// When passed, Xcode will resolve its Package Manager dependencies using the system-defined
        /// accounts (for example, git) instead of the Xcode-defined accounts
        public let resolveDependenciesWithSystemScm: Bool

        /// Disables locking Swift packages. This can speed up generation but does increase risk if packages are not locked
        /// in their declarations.
        public let disablePackageVersionLocking: Bool

        /// Allows to suppress warnings in Xcode about updates to recommended settings added in or below the specified Xcode version. The warnings appear when Xcode version has been upgraded.
        /// It is recommended to set the version option to Xcode's version that is used for development of a project, for example `.lastUpgradeCheck(Version(13, 0, 0))` for Xcode 13.0.0.
        public let lastXcodeUpgradeCheck: Version?

        public static func options(
            xcodeProjectName: TemplateString? = nil,
            organizationName: String? = nil,
            developmentRegion: String? = nil,
            disableShowEnvironmentVarsInScriptPhases: Bool = false,
            resolveDependenciesWithSystemScm: Bool = false,
            disablePackageVersionLocking: Bool = false,
            lastXcodeUpgradeCheck: Version? = nil
        ) -> Self {
            self.init(
                xcodeProjectName: xcodeProjectName,
                organizationName: organizationName,
                developmentRegion: developmentRegion,
                disableShowEnvironmentVarsInScriptPhases: disableShowEnvironmentVarsInScriptPhases,
                resolveDependenciesWithSystemScm: resolveDependenciesWithSystemScm,
                disablePackageVersionLocking: disablePackageVersionLocking,
                lastXcodeUpgradeCheck: lastXcodeUpgradeCheck
            )
        }
    }
}
