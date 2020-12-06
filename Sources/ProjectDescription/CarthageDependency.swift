import Foundation

/// CarthageDependency contains the description of dependency that can by installed using Carthage.
public struct CarthageDependency: Codable, Equatable {
    /// Name of the dependency
    public let name: String

    /// Type of requirement for the given dependency
    public let requirement: Requirement

    /// Set of platforms for  the given dependency
    public let platforms: Set<Platform>

    /// Carthage dependency initailizer
    /// - Parameter name: Name of the dependency
    /// - Parameter requirement: Type of requirement for the given dependency
    /// - Returns Dependency
    public init(name: String, requirement: Requirement, platforms: [Platform]) {
        self.name = name
        self.requirement = requirement
        self.platforms = Set(platforms)
    }
}
