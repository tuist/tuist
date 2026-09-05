import Foundation
import Path
import XCActivityLogParser

// Writes the parsed build data to `output-json` rather than stdout: stdout and
// stderr carry diagnostics only, so the caller can tell a torn write from a
// parser that printed something on its way down.
@main
struct XCActivityLogParserCommand {
    static func main() async {
        let arguments = CommandLine.arguments
        guard arguments.count == 5 else {
            fail(
                "usage: xcactivitylog-parser <xcactivitylog> <cas-analytics-db> <legacy-cas-metadata-dir> <output-json>",
                code: 2
            )
        }

        do {
            let parsed = try await XCActivityLogParser().parse(
                xcactivitylogURL: URL(fileURLWithPath: arguments[1]),
                casAnalyticsDatabasePath: try AbsolutePath(validating: arguments[2]),
                legacyCASMetadataPath: try AbsolutePath(validating: arguments[3])
            )
            try JSONEncoder().encode(parsed).write(to: URL(fileURLWithPath: arguments[4]))
        } catch {
            fail(error.localizedDescription, code: 1)
        }
    }

    private static func fail(_ message: String, code: Int32) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(code)
    }
}
