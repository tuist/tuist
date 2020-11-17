import TSCBasic
import TuistCore
import TuistSupport

// MARK: - Cartfile Content Builder

#warning("TODO: Add unit test!")
final class CartfileContentBuilder {
    
    // MARK: - State
    
    private let dependencies: [CarthageDependency]
    
    // MARK: - Init
    
    init(dependencies: [CarthageDependency]) {
        self.dependencies = dependencies
    }
    
    // MARK: - Build
    
    func build() -> String {
        dependencies
            .map { $0.toString() }
            .joined(separator: "\n")
    }
}

fileprivate extension CarthageDependency {
    func toString() -> String {
        switch requirement {
        case .exact(let version):
            return #"github "\#(name)" == \#(version)"#
        case .upToNextMajor(let version):
            return #"github "\#(name)" ~> \#(version)"#
        case .upToNextMinor(let version):
            return #"github "\#(name)" ~> \#(version)"#
        case .range(let fromVersion, let toVersion):
            #warning("Im not sure if it is possible to handle in cartfile.")
            fatalError("How to handle it?")
        case .branch(let branch):
            return #"github "\#(name)" "\#(branch)""#
        case .revision(let revision):
            return #"github "\#(name)" "\#(revision)""#
        }
    }
}
