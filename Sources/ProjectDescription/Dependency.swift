import Foundation

/// Dependency contains the description of any kind of dependency of your Xcode project.
public struct Dependency: Codable, Equatable {
    /// Name of the dependency
    let name: String

    /// Type of requirement for the given dependency
    let requirement: Dependency.Requirement

    /// Dependecy manager used to retrieve the dependecy
    public let manager: Dependency.Manager

    public init(name: String, requirement: Dependency.Requirement, manager: Dependency.Manager) {
        self.name = name
        self.requirement = requirement
        self.manager = manager
    }

    /// Carthage dependency initailizer
    /// - Parameter name: Name of the dependency
    /// - Parameter requirement: Type of requirement for the given dependency
    /// - Returns Dependency
    public static func carthage(name: String, requirement: Dependency.Requirement) -> Dependency {
        Dependency(name: name, requirement: requirement, manager: .carthage)
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
