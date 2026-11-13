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

    @Test(arguments: [
        ["tuist", "generate", "--quiet", "--no-open"],
        ["tuist", "generate", "run", "--quiet", "--no-open"],
    ])
    func quiet_generation_is_detected_and_global_flag_is_removed(arguments: [String]) {
        #expect(MachineReadableOutput.isQuiet(arguments: arguments))
        #expect(CommandLineArguments.removingGlobalFlags(arguments) == arguments.filter { $0 != "--quiet" })
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

    @Test func childFlagsDoNotChangeOuterOutputOrGetRemoved() {
        let arguments = [
            "tuist",
            "--verbose",
            "run",
            "https://tuist.dev/a/p/previews/id",
            "--",
            "--quiet",
            "--verbose",
            "--json",
            "--",
        ]
        #expect(!MachineReadableOutput.isEnabled(arguments: arguments))
        #expect(!MachineReadableOutput.isQuiet(arguments: arguments))
        #expect(CommandLineArguments.removingGlobalFlags(arguments) == [
            "tuist", "run", "https://tuist.dev/a/p/previews/id", "--", "--quiet", "--verbose", "--json", "--",
        ])
    }
}
