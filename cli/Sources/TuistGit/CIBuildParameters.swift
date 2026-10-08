import FileSystem
import Foundation
import Path

/// Build parameters a CI provider passes to build steps in files rather than as environment
/// variables, keyed by parameter name so they can be looked up alongside the environment.
///
/// TeamCity passes only a few parameters as environment variables. The rest, the branch and the
/// pull request among them, are in the properties files the agent writes for every build:
/// `TEAMCITY_BUILD_PROPERTIES_FILE` names the build's system properties, and its
/// `teamcity.configuration.properties.file` entry names the configuration parameters.
enum CIBuildParameters {
    static func read(environment: [String: String], fileSystem: FileSysteming = FileSystem()) async -> [String: String] {
        guard let buildPropertiesPath = environment["TEAMCITY_BUILD_PROPERTIES_FILE"],
              let buildProperties = await properties(at: buildPropertiesPath, fileSystem: fileSystem)
        else { return [:] }

        var parameters = buildProperties
        if let configurationPropertiesPath = buildProperties["teamcity.configuration.properties.file"],
           let configurationProperties = await properties(at: configurationPropertiesPath, fileSystem: fileSystem)
        {
            parameters.merge(configurationProperties) { buildValue, _ in buildValue }
        }
        // TeamCity calls the default branch `<default>` when no branch specification names it.
        if parameters["teamcity.build.branch"] == "<default>" {
            parameters["teamcity.build.branch"] = nil
        }
        return parameters
    }

    private static func properties(at path: String, fileSystem: FileSysteming) async -> [String: String]? {
        guard let path = try? AbsolutePath(validating: path),
              let contents = try? await fileSystem.readTextFile(at: path)
        else { return nil }
        return parse(contents)
    }

    /// Parses Java's `.properties` format, which is what TeamCity writes the files in: `\`
    /// escapes (`\:` and `\=` among them, which every URL and Windows path carries), `\uXXXX`
    /// code units, `#` and `!` comments, and lines continued with a trailing `\`.
    static func parse(_ contents: String) -> [String: String] {
        let lines = contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { Array(String($0).unicodeScalars) }

        var properties: [String: String] = [:]
        var index = 0
        while index < lines.count {
            var line = Array(lines[index].drop(while: isWhitespace))
            index += 1
            guard let first = line.first, first != "#", first != "!" else { continue }

            while continues(line) {
                line.removeLast()
                guard index < lines.count else { break }
                line += lines[index].drop(while: isWhitespace)
                index += 1
            }

            var keyEnd = 0
            while keyEnd < line.count, !isSeparator(line[keyEnd]) {
                keyEnd += line[keyEnd] == "\\" ? 2 : 1
            }
            keyEnd = min(keyEnd, line.count)

            var valueStart = keyEnd
            while valueStart < line.count, isWhitespace(line[valueStart]) {
                valueStart += 1
            }
            if valueStart < line.count, line[valueStart] == "=" || line[valueStart] == ":" {
                valueStart += 1
            }
            while valueStart < line.count, isWhitespace(line[valueStart]) {
                valueStart += 1
            }

            properties[unescape(line[..<keyEnd])] = unescape(line[valueStart...])
        }
        return properties
    }

    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\u{0C}"
    }

    private static func isSeparator(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "=" || scalar == ":" || isWhitespace(scalar)
    }

    /// A line continues on the next one when it ends with an odd number of backslashes: an even
    /// number is escaped backslashes.
    private static func continues(_ line: [Unicode.Scalar]) -> Bool {
        line.reversed().prefix(while: { $0 == "\\" }).count % 2 == 1
    }

    /// Built from UTF-16 code units so a `\uXXXX` surrogate pair decodes to the character it
    /// encodes.
    private static func unescape(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
        var units: [UInt16] = []
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index]
            index += 1
            guard scalar == "\\" else {
                units.append(contentsOf: scalar.utf16)
                continue
            }
            guard index < scalars.endIndex else { break }
            let escaped = scalars[index]
            index += 1
            switch escaped {
            case "t": units.append(0x09)
            case "n": units.append(0x0A)
            case "r": units.append(0x0D)
            case "f": units.append(0x0C)
            case "u":
                let digits = String(String.UnicodeScalarView(scalars[index ..< min(index + 4, scalars.endIndex)]))
                if digits.count == 4, let unit = UInt16(digits, radix: 16) {
                    units.append(unit)
                    index += 4
                } else {
                    units.append(contentsOf: escaped.utf16)
                }
            default:
                units.append(contentsOf: escaped.utf16)
            }
        }
        return String(decoding: units, as: UTF16.self)
    }
}
