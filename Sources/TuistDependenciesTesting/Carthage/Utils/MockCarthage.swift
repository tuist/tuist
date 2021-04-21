import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockCarthage: Carthaging {
    public init() {}

    var invokedBootstrap = false
    var invokedBootstrapCount = 0
    var invokedBootstrapParameters: BootstrapParameters?
    var invokedBootstrapParametersList = [BootstrapParameters]()
    var bootstrapStub: ((BootstrapParameters) throws -> Void)?

    public func bootstrap(at path: AbsolutePath, platforms: Set<Platform>?, options: Set<CarthageDependencies.Options>?) throws {
        let parameters = BootstrapParameters(
            path: path,
            platforms: platforms,
            options: options
        )

        invokedBootstrap = true
        invokedBootstrapCount += 1
        invokedBootstrapParameters = parameters
        invokedBootstrapParametersList.append(parameters)
        try bootstrapStub?(parameters)
    }

    var invokedUpdate = false
    var invokedUpdateCount = 0
    var invokedUpdateParameters: UpdateParameters?
    var invokedUpdateParametersList = [UpdateParameters]()
    var updateStub: ((UpdateParameters) throws -> Void)?

    public func update(at path: AbsolutePath, platforms: Set<Platform>?, options: Set<CarthageDependencies.Options>?) throws {
        let parameters = UpdateParameters(
            path: path,
            platforms: platforms,
            options: options
        )

        invokedUpdate = true
        invokedUpdateCount += 1
        invokedUpdateParameters = parameters
        invokedUpdateParametersList.append(parameters)
        try updateStub?(parameters)
    }
}

// MARK: - Models

extension MockCarthage {
    struct BootstrapParameters {
        let path: AbsolutePath
        let platforms: Set<Platform>?
        let options: Set<CarthageDependencies.Options>?

        init(
            path: AbsolutePath,
            platforms: Set<Platform>?,
            options: Set<CarthageDependencies.Options>?
        ) {
            self.path = path
            self.platforms = platforms
            self.options = options
        }
    }

    struct UpdateParameters {
        let path: AbsolutePath
        let platforms: Set<Platform>?
        let options: Set<CarthageDependencies.Options>?

        init(
            path: AbsolutePath,
            platforms: Set<Platform>?,
            options: Set<CarthageDependencies.Options>?
        ) {
            self.path = path
            self.platforms = platforms
            self.options = options
        }
    }
}
