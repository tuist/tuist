import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockCarthageCommandGenerator: CarthageCommandGenerating {
    public init() {}

    var invokedCommand = false
    var invokedCommandCount = 0
    var invokedCommandParameters: CommandArgs?
    var invokedCommandParametersList = [CommandArgs]()
    var commandStub: ((CommandArgs) -> [String])?

    public func command(path: AbsolutePath, platforms: Set<Platform>?, options: Set<CarthageDependencies.Options>?) -> [String] {
        invokedCommand = true
        invokedCommandCount += 1
        invokedCommandParameters = CommandArgs(path: path, platforms: platforms, options: options)
        invokedCommandParametersList.append(CommandArgs(path: path, platforms: platforms, options: options))
        if let stub = commandStub {
            return stub(CommandArgs(path: path, platforms: platforms, options: options))
        } else {
            return []
        }
    }
}

// MARK: - Models

extension MockCarthageCommandGenerator {
    struct CommandArgs {
        let path: AbsolutePath
        let platforms: Set<Platform>?
        let options: Set<CarthageDependencies.Options>?
    }
}
