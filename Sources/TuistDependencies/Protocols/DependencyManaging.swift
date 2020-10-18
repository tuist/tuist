import TSCBasic
import TuistSupport

public protocol DependencyManaging {
    var isAvailable: Bool { get }
    
    func install(method: InstallMethod) throws
}
