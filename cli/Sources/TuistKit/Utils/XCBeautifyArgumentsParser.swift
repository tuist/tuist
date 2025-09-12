/// Represents parsed arguments split between xcodebuild and xcbeautify
struct XCBeautifyParsedArguments {
    /// Arguments that remain for xcodebuild
    let remaining: [String]
    /// Arguments that should be passed through to xcbeautify
    let xcbeautify: [String]
}

/// Protocol defining an arguments parser for xcbeautify
protocol XCBeautifyArgumentsParsing {
    /// Parses the provided arguments into xcodebuild and xcbeautify subsets
    /// - Parameter arguments: The full list of CLI arguments
    /// - Returns: A struct containing separated arguments
    func parse(_ arguments: [String]) -> XCBeautifyParsedArguments
}

final class XCBeautifyArgumentsParser: XCBeautifyArgumentsParsing {
    func parse(_ arguments: [String]) -> XCBeautifyParsedArguments {
        var passthroughArgs: [String] = []
        var remainingArgs: [String] = []
        var skipNext = false

        for (index, arg) in arguments.enumerated() {
            if skipNext {
                skipNext = false
                continue
            }

            if arg.starts(with: "--xcbeautify-") {
                let beautifyArg = "--" + arg.dropFirst("--xcbeautify-".count)
                if index + 1 < arguments.count {
                    let next = arguments[index + 1]
                    if !next.starts(with: "-") {
                        passthroughArgs.append(contentsOf: [beautifyArg, next])
                        skipNext = true
                    } else {
                        passthroughArgs.append(beautifyArg)
                    }
                } else {
                    passthroughArgs.append(beautifyArg)
                }
            } else {
                remainingArgs.append(arg)
            }
        }

        return XCBeautifyParsedArguments(remaining: remainingArgs, xcbeautify: passthroughArgs)
    }
}
