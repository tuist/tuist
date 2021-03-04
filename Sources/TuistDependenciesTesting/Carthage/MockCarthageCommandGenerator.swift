import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockCarthageCommandGenerator: CarthageCommandGenerating {
    public init() {}

    var invokedCommand = false
    var invokedCommandCount = 0
    var invokedCommandParameters: (path: AbsolutePath, produceXCFrameworks: Bool, noUseBinaries: Bool, platforms: Set<Platform>?)?
    var invokedCommandParametersList = [(path: AbsolutePath, produceXCFrameworks: Bool, noUseBinaries: Bool, platforms: Set<Platform>?)]()
    var commandStub: ((AbsolutePath, Bool, Bool, Set<Platform>?) -> [String])?

    public func command(path: AbsolutePath, produceXCFrameworks: Bool, noUseBinaries: Bool, platforms: Set<Platform>?) -> [String] {
        invokedCommand = true
        invokedCommandCount += 1
        invokedCommandParameters = (path, produceXCFrameworks, noUseBinaries, platforms)
        invokedCommandParametersList.append((path, produceXCFrameworks, noUseBinaries, platforms))
        if let stub = commandStub {
            return stub(path, produceXCFrameworks, noUseBinaries, platforms)
        } else {
            return []
        }
    }
}
