import TSCBasic
import TuistCore
import TuistSupport

@testable import TuistLoader

public class MockDependenciesModelLoader: DependenciesModelLoading {
    public init() {}
    
    var invokedLoadDependencies = false
    var invokedLoadDependenciesCount = 0
    var invokedLoadDependenciesParameters: AbsolutePath?
    var invokedLoadDependenciesParemetersList = [AbsolutePath]()
    var loadDependenciesStub: ((AbsolutePath) throws -> [CarthageDependency])?
    
    public func loadDependencies(at path: AbsolutePath) throws -> [CarthageDependency] {
        invokedLoadDependencies = true
        invokedLoadDependenciesCount += 1
        invokedLoadDependenciesParameters = (path)
        invokedLoadDependenciesParemetersList.append((path))
        
        if let stub = loadDependenciesStub {
            return try stub(path)
        } else {
            return []
        }
    }
}
