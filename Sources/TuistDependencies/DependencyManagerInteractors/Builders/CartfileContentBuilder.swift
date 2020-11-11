import TSCBasic
import TuistSupport

#warning("Is it a correct import?")
import ProjectDescription

// MARK: - Cartfile Content Builder

#warning("TODO: Add unit test!")
final class CartfileContentBuilder {
    
    // MARK: - State
    
    private let dependencies: [Dependency]
    
    // MARK: - Init
    
    init(dependencies: [Dependency]) {
        self.dependencies = dependencies
    }
    
    // MARK: - Build
    
    func build() -> String {
        dependencies
            .map { $0.toString() }
            .joined(separator: "\n")
    }
}

fileprivate extension ProjectDescription.Dependency {
    func toString() -> String {
        "github \(name) \(requirement.toString())"
    }
}

fileprivate extension ProjectDescription.Dependency.Requirement {
    func toString() -> String {
        switch self {
        case .exact(let version):
            return "= \(version.description)"
        }
    }
}
