import TSCBasic
import TuistSupport

public protocol DependencyManagerInteracting {
    var isAvailable: Bool { get }
    
    func install(method: InstallDependenciesMethod) throws
}
