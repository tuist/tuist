import TSCBasic
import TuistSupport

// MARK: - Cartfile Content Builder

#warning("TODO: Add unit test!")
final class CartfileContentBuilder {
    
    // MARK: - Models
    
    #warning("How to handle dependencies versioning?")
    enum Dependency {
        case github(name: String, version: String)
        
        var name: String {
            switch self {
            case .github(let name, _):
                return name.components(separatedBy: "/").last ?? name
            }
        }
        
        fileprivate func toString() -> String {
            switch self {
            case .github(let name, let version):
                return #"github "\#(name)" == \#(version)"#
            }
        }
    }
    
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
