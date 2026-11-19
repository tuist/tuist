import ArgumentParser
import Testing
@testable import TuistBuildCommand

struct BuildOnceCommandTests {
    @Test(arguments: ["struo", "once"])
    func parsesListWithCanonicalNameAndLegacyAlias(name: String) throws {
        let command = try BuildCommand.parseAsRoot([name, "list", "--project", "acme/app", "--kind", "test", "--json"])
        let list = try #require(command as? BuildOnceListCommand)
        #expect(list.project == "acme/app")
        #expect(list.kind == .test)
        #expect(list.json)
    }

    @Test(arguments: ["struo", "once"])
    func parsesShowWithCanonicalNameAndLegacyAlias(name: String) throws {
        let command = try BuildCommand.parseAsRoot([name, "show", "run-1", "--project", "acme/app"])
        let show = try #require(command as? BuildOnceShowCommand)
        #expect(show.runId == "run-1")
        #expect(show.project == "acme/app")
    }

    @Test func helpUsesStruo() {
        #expect(BuildOnceCommand.configuration.commandName == "struo")
        #expect(BuildOnceCommand.configuration.aliases == ["once"])
        #expect(BuildOnceCommand.helpMessage().contains("Struo"))
        #expect(BuildOnceListCommand.helpMessage().contains("Struo runs"))
        #expect(BuildOnceShowCommand.helpMessage().contains("Struo run"))
    }
}
