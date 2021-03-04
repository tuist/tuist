import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockCarthageCommandGenerator: CarthageCommandGenerating {
    public init() {}

    var invokedCommand = false
    var invokedCommandCount = 0
    var invokedCommandParameters: CommandArgs?
    var invokedCommandParametersList = [CommandArgs]()
    var commandStub: ((AbsolutePath, Bool, Bool, Set<Platform>?) -> [String])?

    public func command(path: AbsolutePath, produceXCFrameworks: Bool, noUseBinaries: Bool, platforms: Set<Platform>?) -> [String] {
        invokedCommand = true
        invokedCommandCount += 1
        invokedCommandParameters = CommandArgs(path: path, produceXCFrameworks: produceXCFrameworks, noUseBinaries: noUseBinaries, platforms: platforms)
        invokedCommandParametersList.append(CommandArgs(path: path, produceXCFrameworks: produceXCFrameworks, noUseBinaries: noUseBinaries, platforms: platforms))
        if let stub = commandStub {
            return stub(path, produceXCFrameworks, noUseBinaries, platforms)
        } else {
            return []
        }
    }
}

// MARK: - Models

extension MockCarthageCommandGenerator {
    struct CommandArgs {
        let path: AbsolutePath
        let produceXCFrameworks: Bool
        let noUseBinaries: Bool
        let platforms: Set<Platform>?
    }
}
