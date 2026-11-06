import ArgumentParser
import Testing
import TuistNooraExtension
@testable import TuistKit

struct CoverageCompleteCommandTests {
    @Test func jsonOutputGoesThroughNoora() throws {
        let command = try CoverageCommand.parseAsRoot(["complete", "--json"])

        let nooraReadyCommand = try #require(command as? NooraReadyCommand)
        #expect(nooraReadyCommand.jsonThroughNoora)
        #expect((command as? CoverageCompleteCommand)?.json == true)
    }
}
