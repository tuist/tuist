import Foundation

/// Protocol that defines an interface to parse the xcodebuild output
protocol XcodeBuildOutputParsing {
    /// Parsers a line from the xcodebuild output and maps it into an XcodeBuildOutputEvent.
    ///
    /// - Parameter line: Line to be parsed.
    /// - Returns: Event that the line is associated to.
    func parse(line: String) -> XcodeBuildOutputEvent?
}

final class XcodeBuildOutputParser: XcodeBuildOutputParsing {
    private static let analyzeRegex: NSRegularExpression = try! NSRegularExpression(pattern: "^Analyze(?:Shallow)?\\s(.*\\/(.*\\.(?:m|mm|cc|cpp|c|cxx)))\\s*",
                                                                                    options: [])

    /// Parsers a line from the xcodebuild output and maps it into an XcodeBuildOutputEvent.
    ///
    /// - Parameter line: Line to be parsed.
    /// - Returns: Event that the line is associated to.
    func parse(line: String) -> XcodeBuildOutputEvent? {
        let range = NSRange(location: 0, length: line.count)
        let nsLine = NSString(string: line)

        // Analyze event
        if let match = XcodeBuildOutputParser.analyzeRegex.firstMatch(in: line,
                                                                      options: [],
                                                                      range: range) {
            let filePath = nsLine.substring(with: match.range(at: 1))
            let name = nsLine.substring(with: match.range(at: 2))
            return .analyze(filePath: filePath, name: name)
        }

        return nil
    }
}
