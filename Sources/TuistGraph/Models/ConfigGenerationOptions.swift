import TSCUtility

extension Config {
    /// Contains options related to the project generation.
    public struct GenerationOptions: Codable, Hashable {
        /// When passed, Xcode will resolve its Package Manager dependencies using the system-defined
        /// accounts (for example, git) instead of the Xcode-defined accounts
        public let resolveDependenciesWithSystemScm: Bool

        /// IDE template macros
        public let templateMacros: IDETemplateMacros?

        /// Disables locking Swift packages. This can speed up generation but does increase risk if packages are not locked
        /// in their declarations.
        public let disablePackageVersionLocking: Bool

        public init(
            templateMacros: IDETemplateMacros?,
            resolveDependenciesWithSystemScm: Bool,
            disablePackageVersionLocking: Bool
        ) {
            self.templateMacros = templateMacros
            self.resolveDependenciesWithSystemScm = resolveDependenciesWithSystemScm
            self.disablePackageVersionLocking = disablePackageVersionLocking
        }
    }
}
