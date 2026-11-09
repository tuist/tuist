import ArgumentParser
import TestCoverageAttribution
import Testing
@testable import TuistAccountCommand

@Suite(.coverageAttribution)
struct AccountTokensListCommandTests {
    @Test func jsonOutputGoesThroughNoora() throws {
        let command = try AccountTokensListCommand.parse(["tuist", "--json"])

        #expect(command.jsonThroughNoora)
        #expect(command.json)
    }
}
