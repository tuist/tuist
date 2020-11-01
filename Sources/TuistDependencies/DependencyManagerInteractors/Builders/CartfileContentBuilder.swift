import TSCBasic
import TuistSupport

// MARK: - Cartfile Content Builder Error

enum CartfileContentBuilderError: FatalError {
    case unspecifiedDependencies
    
    /// Error type.
    var type: ErrorType {
        switch self {
        case .unspecifiedDependencies:
            return .abort
        }
    }

    /// Description.
    var description: String {
        switch self {
        case .unspecifiedDependencies:
            #warning("Provide description")
            return ""
        }
    }
}

// MARK: - Cartfile Content Builder

#warning("Add unit test!")
final class CartfileContentBuilder {
    
    // MARK: - Models
    
    #warning("How to handle dependencies versioning?")
    enum Dependency {
        case github(name: String, version: String)
        
        fileprivate func toString() -> String {
            switch self {
            case .github(let name, let version):
                return #"github "\#(name)" == \#(version)"#
            }
        }
    }
    
    // MARK: - State
    
    var depedencies: [Dependency] = []
    
    // MARK: - Configurators
    
    @discardableResult
    func dependnecy(_ dependency: Dependency) -> Self {
        self.depedencies.append(dependency)
        return self
    }
    
    @discardableResult
    func dependnecies(_ dependencies: [Dependency]) -> Self {
        self.depedencies.append(contentsOf: dependencies)
        return self
    }
    
    // MARK: - Build
    
    func build() throws -> String {
        guard !depedencies.isEmpty else {
            throw CartfileContentBuilderError.unspecifiedDependencies
        }
        
        return depedencies
            .map { $0.toString() }
            .joined(separator: "\n")
    }
}
