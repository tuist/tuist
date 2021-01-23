import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockCarthageCommandGenerator: CarthageCommandGenerating {
    public init() {}

    var invokedCommand = false
    var invokedCommandCount = 0
    var invokedCommandParameters: (path: AbsolutePath, platforms: Set<Platform>?)?
    var invokedCommandParametersList = [(path: AbsolutePath, platforms: Set<Platform>?)]()
    var commandStub: ((AbsolutePath, Set<Platform>?) -> [String])?

    public func command(path: AbsolutePath, platforms: Set<Platform>?) -> [String] {
        invokedCommand = true
        invokedCommandCount += 1
        invokedCommandParameters = (path, platforms)
        invokedCommandParametersList.append((path, platforms))
        if let stub = commandStub {
            return stub(path, platforms)
        } else {
            return []
        }
    }
}
