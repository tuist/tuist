public enum SwiftPackageManagerArguments {
    public static func removingCustomScratchPathArguments(_ arguments: [String]) -> [String] {
        var result: [String] = []
        var skipNext = false

        for argument in arguments {
            if skipNext {
                skipNext = false
                continue
            }

            if argument == "--scratch-path" || argument == "--build-path" {
                skipNext = true
                continue
            }

            if argument.hasPrefix("--scratch-path=") || argument.hasPrefix("--build-path=") {
                continue
            }

            result.append(argument)
        }

        return result
    }
}
