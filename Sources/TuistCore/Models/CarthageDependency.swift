import Foundation

/// CarthageDependency contains the description of a dependency to be fetched with Carthage.
public struct CarthageDependency {
    /// Name of the dependency
    public let name: String

    /// Type of requirement for the given dependency
    public let requirement: Requirement

    /// Set of platforms for  the given dependency
    public let platforms: Set<Platform>

    public init(name: String, requirement: Requirement, platforms: Set<Platform>) {
        self.name = name
        self.requirement = requirement
        self.platforms = platforms
    }
}
