import ArgumentParser
import Testing
@testable import TuistAccountCommand

struct AccountTokensListCommandTests {
    @Test func jsonOutputGoesThroughNoora() throws {
        let command = try AccountTokensListCommand.parse(["tuist", "--json"])

        #expect(command.jsonThroughNoora)
        #expect(command.json)
    }
}
