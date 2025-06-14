import FileSystem
import Foundation
import Path
import Testing

public struct TuistTestFixtureTestingTrait: TestTrait, SuiteTrait, TestScoping {
    let fixtureDirectory: AbsolutePath

    init(fixture: String) {
        fixtureDirectory = Fixtures.directory.appending(component: fixture)
    }

    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        let fileSystem = FileSystem()
        try await fileSystem.runInTemporaryDirectory { temporaryDirectory in
            let fixtureTemporaryDirectory = temporaryDirectory.appending(
                component: fixtureDirectory.basename
            )
            try await fileSystem.copy(fixtureDirectory, to: fixtureTemporaryDirectory)
            try await TuistTest.$fixtureDirectory.withValue(fixtureTemporaryDirectory) {
                try await function()
            }
        }
    }
}

extension Trait where Self == TuistTestFixtureTestingTrait {
    public static func withFixture(_ fixture: String) -> Self {
        return Self(fixture: fixture)
    }
}
