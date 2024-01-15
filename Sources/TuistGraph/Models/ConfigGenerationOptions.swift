import TSCBasic
import TSCUtility

extension Config {
    public struct GenerationOptions: Codable, Hashable {
        public enum StaticSideEffectsWarningTargets: Codable, Hashable, Equatable {
            case all
            case none
            case excluding([String])
        }

        public let resolveDependenciesWithSystemScm: Bool
        public let disablePackageVersionLocking: Bool
        public let clonedSourcePackagesDirPath: AbsolutePath?
        public let staticSideEffectsWarningTargets: StaticSideEffectsWarningTargets
        public let enforceExplicitDependencies: Bool

        public init(
            resolveDependenciesWithSystemScm: Bool,
            disablePackageVersionLocking: Bool,
            clonedSourcePackagesDirPath: AbsolutePath? = nil,
            staticSideEffectsWarningTargets: StaticSideEffectsWarningTargets = .all,
            enforceExplicitDependencies: Bool = false
        ) {
            self.resolveDependenciesWithSystemScm = resolveDependenciesWithSystemScm
            self.disablePackageVersionLocking = disablePackageVersionLocking
            self.clonedSourcePackagesDirPath = clonedSourcePackagesDirPath
            self.staticSideEffectsWarningTargets = staticSideEffectsWarningTargets
            self.enforceExplicitDependencies = enforceExplicitDependencies
        }
    }
}
