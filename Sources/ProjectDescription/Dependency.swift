import Foundation

/// Dependency contains the description of any kind of dependency of your Xcode project.
public struct Dependency: Codable, Equatable {

    /// Name of the dependency
    let name: String

    /// Type of requirement for the given dependency
    let requirement: Dependency.Requirement

    public init(name: String, requirement: Dependency.Requirement) {
        self.name = name
        self.requirement = requirement
    }

    /// Carthage dependency initailizer
    /// - Parameter name: Name of the dependency
    /// - Parameter requirement: Type of requirement for the given dependency
    /// - Returns Dependency
    public static func carthage(name: String, requirement: Dependency.Requirement) -> Dependency {
        Dependency(name: name, requirement: requirement)
    }

    public static func == (lhs: Dependency, rhs: Dependency) -> Bool {
        lhs.name == rhs.name && lhs.requirement == rhs.requirement
    }
}

public struct Dependencies: Codable, Equatable {
    private let dependencies: [Dependency]

    public init(_ dependencies: [Dependency]) {
        self.dependencies = dependencies
        dumpIfNeeded(self)
    }
}
