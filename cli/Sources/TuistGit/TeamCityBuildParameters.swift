import FileSystem
import Foundation
import Path

/// The parameters of a TeamCity build that say which commit, branch, and pull request it is for.
///
/// TeamCity passes only a few of them to build steps as environment variables. The rest are in the
/// properties files the agent writes for every build: `TEAMCITY_BUILD_PROPERTIES_FILE` names the
/// build's system properties, and its `teamcity.configuration.properties.file` entry names the
/// configuration parameters, among them the branch and the pull request.
struct TeamCityBuildParameters: Equatable {
    let parameters: [String: String]

    static func read(environment: [String: String], fileSystem: FileSysteming = FileSystem()) async -> TeamCityBuildParameters? {
        guard environment["TEAMCITY_VERSION"] != nil,
              let buildPropertiesPath = environment["TEAMCITY_BUILD_PROPERTIES_FILE"],
              let buildProperties = await properties(at: buildPropertiesPath, fileSystem: fileSystem)
        else { return nil }

        var parameters = buildProperties
        if let configurationPropertiesPath = buildProperties["teamcity.configuration.properties.file"],
           let configurationProperties = await properties(at: configurationPropertiesPath, fileSystem: fileSystem)
        {
            parameters.merge(configurationProperties) { buildValue, _ in buildValue }
        }
        return TeamCityBuildParameters(parameters: parameters)
    }

    var pullRequestNumber: Int? {
        parameters["teamcity.pullRequest.number"].flatMap { Int($0) }
    }

    var targetBranch: String? {
        parameters["teamcity.pullRequest.target.branch"].map(Self.branchName)
    }

    /// The ref the build checked out, such as `refs/heads/main` or, for a GitHub pull request,
    /// `refs/pull/<n>/head`. TeamCity names one per VCS root, so it is only known for a build with
    /// a single root.
    var ref: String? {
        if let ref = value(perRoot: "teamcity.build.vcs.branch."), ref.hasPrefix("refs/") {
            return ref
        }
        return pullRequestNumber.map { "refs/pull/\($0)/head" }
    }

    /// For a pull request, its source branch, which TeamCity leaves unset for one from a fork. For
    /// any other build, the branch it checked out.
    var branch: String? {
        if pullRequestNumber != nil || ref?.hasPrefix("refs/pull/") == true {
            return parameters["teamcity.pullRequest.source.branch"].map(Self.branchName)
        }
        if let ref, ref.hasPrefix("refs/heads/") {
            return Self.branchName(ref)
        }
        // `<default>` is the logical name of the default branch when the branch specification
        // leaves it unnamed.
        return parameters["teamcity.build.branch"].flatMap { $0 == "<default>" ? nil : $0 }
    }

    var commitSHA: String? {
        value(named: "build.vcs.number", perRoot: "build.vcs.number.")
    }

    var remoteURL: String? {
        value(named: "vcsroot.url", perRoot: "vcsroot.", suffix: ".url")
    }

    private func value(named name: String? = nil, perRoot prefix: String, suffix: String = "") -> String? {
        if let name, let value = parameters[name] { return value }
        let values = parameters
            .filter { $0.key != name && $0.key.hasPrefix(prefix) && $0.key.hasSuffix(suffix) }
            .map(\.value)
        return values.count == 1 ? values.first : nil
    }

    private static func branchName(_ name: String) -> String {
        name.hasPrefix("refs/heads/") ? String(name.dropFirst("refs/heads/".count)) : name
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
