import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockCarthageCommandGenerator: CarthageCommandGenerating {
    public init() {}

    var invokedCommand = false
    var invokedCommandCount = 0
    var invokedCommandParameters: (method: InstallDependenciesMethod, path: AbsolutePath, platforms: Set<Platform>?)?
    var invokedCommandParametersList = [(method: InstallDependenciesMethod, path: AbsolutePath, platforms: Set<Platform>?)]()
    var commandStub: ((InstallDependenciesMethod, AbsolutePath, Set<Platform>?) -> [String])?

    public func command(method: InstallDependenciesMethod, path: AbsolutePath, platforms: Set<Platform>?) -> [String] {
        invokedCommand = true
        invokedCommandCount += 1
        invokedCommandParameters = (method, path, platforms)
        invokedCommandParametersList.append((method, path, platforms))
        if let stub = commandStub {
            return stub(method, path, platforms)
        } else {
            return []
        }
    }
}
