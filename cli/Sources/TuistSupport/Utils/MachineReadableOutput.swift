public enum MachineReadableOutput {
    private static let machineReadableCommands: Set<String> = [
        "dump",
    ]

    private static let ignoredGlobalFlags: Set<String> = [
        "--quiet",
        "--verbose",
    ]

    public static func isEnabled(arguments: [String]) -> Bool {
        if arguments.contains("--json") {
            return true
        }

        let commandArguments = arguments
            .dropFirst()
            .filter { !ignoredGlobalFlags.contains($0) }

        guard let command = commandArguments.first else {
            return false
        }

        return machineReadableCommands.contains(command)
    }

    public static func isQuiet(arguments: [String]) -> Bool {
        arguments.contains("--quiet")
    }
}
