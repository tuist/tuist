import TSCBasic
import TuistSupport

public protocol DependencyManagerInteracting {
    func install(at path: AbsolutePath, method: InstallDependenciesMethod) throws
}
