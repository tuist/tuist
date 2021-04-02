import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockCarthageCommandGenerator: CarthageCommandGenerating {
    public init() {}

    var invokedCommand = false
    var invokedCommandCount = 0
    var invokedCommandParameters: CommandParameters?
    var invokedCommandParametersList = [CommandParameters]()
    var commandStub: ((CommandParameters) -> [String])?

    public func command(path: AbsolutePath, platforms: Set<Platform>?, options: Set<CarthageDependencies.Options>?) -> [String] {
        let parameters = CommandParameters(
            path: path,
            platforms: platforms,
            options: options
        )

        invokedCommand = true
        invokedCommandCount += 1
        invokedCommandParameters = parameters
        invokedCommandParametersList.append(parameters)
        if let stub = commandStub {
            return stub(parameters)
        } else {
            return []
        }
    }
}

// MARK: - Models

extension MockCarthageCommandGenerator {
    struct CommandParameters {
        let path: AbsolutePath
        let platforms: Set<Platform>?
        let options: Set<CarthageDependencies.Options>?
    }
}
