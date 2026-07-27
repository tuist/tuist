import Foundation
import Testing
import TuistTesting
@testable import TuistKit

struct HashAcceptanceTests {
    @Test(.withFixture("generated_ios_app_with_frameworks"), .withMockedDependencies())
    func xcode_project_ios_framework() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(HashCacheCommand.self, ["--path", fixtureDirectory.pathString])
        TuistTest.expectLogs("Framework1 -", at: .info, <=)
        TuistTest.expectLogs("Framework2-iOS -", at: .info, <=)
        TuistTest.expectLogs("Framework2-macOS -", at: .info, <=)
        TuistTest.expectLogs("Framework3 -", at: .info, <=)
        TuistTest.expectLogs("Framework4 -", at: .info, <=)
        TuistTest.expectLogs("Framework5 -", at: .info, <=)
    }
}
