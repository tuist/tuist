import TSCBasic
import TuistGraph
import TuistSupport

@testable import TuistLoader

public class MockDependenciesModelLoader: DependenciesModelLoading {
    public init() {}

    public var invokedLoadDependencies = false
    public var invokedLoadDependenciesCount = 0
    public var invokedLoadDependenciesParameters: AbsolutePath?
    public var invokedLoadDependenciesParemetersList = [AbsolutePath]()
    public var loadDependenciesStub: ((AbsolutePath) throws -> Dependencies)?

    public func loadDependencies(at path: AbsolutePath) throws -> Dependencies {
        invokedLoadDependencies = true
        invokedLoadDependenciesCount += 1
        invokedLoadDependenciesParameters = path
        invokedLoadDependenciesParemetersList.append(path)

        if let stub = loadDependenciesStub {
            return try stub(path)
        } else {
            return Dependencies(carthage: nil, swiftPackageManager: nil, platforms: [])
        }
    }
}
