import Foundation

/// Dependency contains the description of any kind of dependency of your Xcode project.
public struct Dependency: Codable, Equatable {
    /// Name of the dependency
    let name: String

    /// Type of requirement for the given dependency
    let requirement: Dependency.Requirement

    /// Dependecy manager used to retrieve the dependecy
    public let manager: Dependency.Manager

    /// Set of platforms for  the given dependency
    public let platforms: Set<Platform>

    public init(name: String,
                requirement: Dependency.Requirement,
                manager: Dependency.Manager,
                platforms: [Platform])
    {
        self.name = name
        self.requirement = requirement
        self.manager = manager
        self.platforms = Set(platforms)
    }

    /// Carthage dependency initailizer
    /// - Parameter name: Name of the dependency
    /// - Parameter requirement: Type of requirement for the given dependency
    /// - Returns Dependency
    public static func carthage(name: String,
                                requirement: Dependency.Requirement,
                                platforms: [Platform]) -> Dependency
    {
        Dependency(name: name, requirement: requirement, manager: .carthage, platforms: platforms)
    }

    public static func == (lhs: Dependency, rhs: Dependency) -> Bool {
        lhs.name == rhs.name && lhs.requirement == rhs.requirement
    }
}

public struct Dependencies: Codable, Equatable {
    public let dependencies: [Dependency]

    public init(_ dependencies: [Dependency]) {
        self.dependencies = dependencies
        dumpIfNeeded(self)
    }
}
