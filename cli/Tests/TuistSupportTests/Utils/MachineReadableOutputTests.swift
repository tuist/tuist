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

    @Test func isQuiet_whenQuietFlagIsPresent() {
        let arguments = ["tuist", "--quiet", "generate"]

        #expect(MachineReadableOutput.isQuiet(arguments: arguments))
    }

    @Test func isQuiet_whenQuietFlagIsNotPresent() {
        let arguments = ["tuist", "generate"]

        #expect(MachineReadableOutput.isQuiet(arguments: arguments) == false)
    }

    @Test func isEnabled_whenQuietFlagIsPresentForHumanReadableCommand() {
        let arguments = ["tuist", "--quiet", "generate"]

        #expect(MachineReadableOutput.isEnabled(arguments: arguments) == false)
    }

    @Test func isEnabled_whenQuietFlagIsPresentForMachineReadableCommand() {
        let arguments = ["tuist", "--quiet", "dump"]

        #expect(MachineReadableOutput.isEnabled(arguments: arguments))
    }
}
