import Foundation
import Testing
import TuistTesting

@testable import TuistKit

struct CacheAcceptanceTests {
    @Test(.withFixture("generated_ios_app_with_frameworks"), .withMockedDependencies())
    func ios_app_with_frameworks() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(
            CacheCommand.self,
            ["--print-hashes", "--path", fixtureDirectory.pathString]
        )
    }
}
