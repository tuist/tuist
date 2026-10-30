public enum CommandLineArguments {
    /// Arguments after `--` belong to the child, including flags that Tuist also recognizes.
    public static func beforePassthrough(_ arguments: [String]) -> [String] {
        Array(arguments.prefix(while: { $0 != "--" }))
    }

    public static func removingGlobalFlags(_ arguments: [String]) -> [String] {
        let boundary = arguments.firstIndex(of: "--") ?? arguments.endIndex
        return arguments[..<boundary].filter { $0 != "--verbose" && $0 != "--quiet" }
            + arguments[boundary...]
    }
}
