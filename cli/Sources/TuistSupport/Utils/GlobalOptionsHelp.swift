#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#endif

import Foundation

/// Renders the flags that apply to every command into the generated help screens.
///
/// `--verbose` and `--quiet` are filtered out of the arguments before they reach ArgumentParser,
/// and are read back from the raw process arguments instead. No command declares them, so
/// ArgumentParser has nothing to render for them and they would otherwise be absent from every
/// `--help` screen.
public enum GlobalOptionsHelp {
    private static let indent = 2
    private static let labelColumnWidth = 26
    private static let defaultScreenWidth = 80

    private static let options: [(label: String, abstract: String)] = [
        ("--verbose", "Display verbose logs, including the debug information commands emit."),
        ("--quiet", "Silence all the output except errors."),
    ]

    /// Whether the given arguments ask for a help screen.
    ///
    /// Version and `--experimental-dump-help` requests also exit cleanly, so a clean exit on its
    /// own is not enough to tell that ArgumentParser is about to print a help screen.
    public static func isHelpRequest(arguments: [String]) -> Bool {
        arguments.contains("--help") || arguments.contains("-h")
            || arguments.dropFirst().first == "help"
    }

    public static func appending(to helpText: String, screenWidth: Int) -> String {
        var text = helpText
        while text.hasSuffix("\n") {
            text.removeLast()
        }
        return text + "\n\n" + section(screenWidth: screenWidth) + "\n"
    }

    public static func section(screenWidth: Int) -> String {
        (["GLOBAL OPTIONS:"] + options.map {
            render(label: $0.label, abstract: $0.abstract, screenWidth: screenWidth)
        })
        .joined(separator: "\n")
    }

    /// Mirrors how ArgumentParser sizes help screens so that the section wraps at the same column
    /// as the rest of the screen.
    public static func screenWidth(environment: [String: String] = ProcessInfo.processInfo.environment) -> Int {
        if let columns = environment["COLUMNS"].flatMap(Int.init), columns > 0 {
            return columns
        }
        return reportedScreenWidth() ?? defaultScreenWidth
    }

    private static func reportedScreenWidth() -> Int? {
        var size = winsize()
        #if os(Linux)
            let request = UInt(TIOCGWINSZ)
        #else
            let request = TIOCGWINSZ
        #endif
        guard ioctl(STDOUT_FILENO, request, &size) == 0, size.ws_col > 0 else { return nil }
        return Int(size.ws_col)
    }

    private static func render(label: String, abstract: String, screenWidth: Int) -> String {
        let paddedLabel = String(repeating: " ", count: indent) + label
        let continuationIndent = String(repeating: " ", count: labelColumnWidth)
        let lines = wrap(abstract, to: max(screenWidth - labelColumnWidth, 1))

        guard paddedLabel.count < labelColumnWidth else {
            return ([paddedLabel] + lines.map { continuationIndent + $0 }).joined(separator: "\n")
        }
        let firstLine = paddedLabel + String(repeating: " ", count: labelColumnWidth - paddedLabel.count)
            + (lines.first ?? "")
        return ([firstLine] + lines.dropFirst().map { continuationIndent + $0 }).joined(separator: "\n")
    }

    private static func wrap(_ text: String, to width: Int) -> [String] {
        var lines: [String] = []
        var line = ""
        for word in text.split(separator: " ") {
            if line.isEmpty {
                line = String(word)
            } else if line.count + 1 + word.count <= width {
                line += " " + word
            } else {
                lines.append(line)
                line = String(word)
            }
        }
        if !line.isEmpty {
            lines.append(line)
        }
        return lines
    }
}
