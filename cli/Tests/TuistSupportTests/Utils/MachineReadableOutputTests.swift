import Testing
@testable import TuistSupport

struct MachineReadableOutputTests {
    @Test func isEnabled_whenJSONFlagIsPresent() {
        let arguments = ["tuist", "--json", "generate"]

        #expect(MachineReadableOutput.isEnabled(arguments: arguments))
    }

    @Test func isEnabled_whenDumpCommandIsExecuted() {
        let arguments = ["tuist", "dump"]

        #expect(MachineReadableOutput.isEnabled(arguments: arguments))
    }

    @Test func isEnabled_whenDumpCommandFollowsGlobalFlags() {
        let arguments = ["tuist", "--verbose", "dump"]

        #expect(MachineReadableOutput.isEnabled(arguments: arguments))
    }

    @Test func isDisabled_forHumanReadableCommands() {
        let arguments = ["tuist", "generate"]

        #expect(MachineReadableOutput.isEnabled(arguments: arguments) == false)
    }
}
