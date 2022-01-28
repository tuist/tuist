import TSCBasic
import TuistGraph
import TuistSupport

@testable import TuistLoader

public class MockDependenciesModelLoader: DependenciesModelLoading {
    public init() {}

    public var invokedLoadDependencies = false
    public var invokedLoadDependenciesCount = 0
    public var invokedLoadDependenciesParameters: (AbsolutePath, Plugins)?
    public var invokedLoadDependenciesParemetersList = [(AbsolutePath, Plugins)]()
    public var loadDependenciesStub: ((AbsolutePath, Plugins) throws -> Dependencies)?

    public func loadDependencies(at path: AbsolutePath, with plugins: Plugins) throws -> Dependencies {
        invokedLoadDependencies = true
        invokedLoadDependenciesCount += 1
        invokedLoadDependenciesParameters = (path, plugins)
        invokedLoadDependenciesParemetersList.append((path, plugins))

        if let stub = loadDependenciesStub {
            return try stub(path, plugins)
        } else {
            return Dependencies(carthage: nil, swiftPackageManager: nil, platforms: [])
        }
    }
}
