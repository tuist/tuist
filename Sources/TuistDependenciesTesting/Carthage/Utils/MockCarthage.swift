import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockCarthage: Carthaging {
    public init() {}

    var invokedBootstrap = false
    var bootstrapStub: ((BootstrapParameters) throws -> Void)?

    public func bootstrap(at path: AbsolutePath, platforms: Set<Platform>, options: Set<CarthageDependencies.Options>) throws {
        let parameters = BootstrapParameters(
            path: path,
            platforms: platforms,
            options: options
        )

        invokedBootstrap = true
        try bootstrapStub?(parameters)
    }

    var invokedUpdate = false
    var updateStub: ((UpdateParameters) throws -> Void)?

    public func update(at path: AbsolutePath, platforms: Set<Platform>, options: Set<CarthageDependencies.Options>) throws {
        let parameters = UpdateParameters(
            path: path,
            platforms: platforms,
            options: options
        )

        invokedUpdate = true
        try updateStub?(parameters)
    }
}

// MARK: - Models

extension MockCarthage {
    struct BootstrapParameters {
        let path: AbsolutePath
        let platforms: Set<Platform>
        let options: Set<CarthageDependencies.Options>

        init(
            path: AbsolutePath,
            platforms: Set<Platform>,
            options: Set<CarthageDependencies.Options>
        ) {
            self.path = path
            self.platforms = platforms
            self.options = options
        }
    }

    struct UpdateParameters {
        let path: AbsolutePath
        let platforms: Set<Platform>
        let options: Set<CarthageDependencies.Options>

        init(
            path: AbsolutePath,
            platforms: Set<Platform>,
            options: Set<CarthageDependencies.Options>
        ) {
            self.path = path
            self.platforms = platforms
            self.options = options
        }
    }
}
