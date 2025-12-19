import FileSystem
import Foundation
import Mockable
import Path

@Mockable
protocol MCPCodexConfigurationFileControlling {
    func update(at configPath: AbsolutePath) async throws
}

struct MCPCodexConfigurationFileController: MCPCodexConfigurationFileControlling {
    private let fileSystem: FileSystem
    private let serverCommandResolver: MCPServerCommandResolving

    init() {
        self.init(fileSystem: FileSystem(), serverCommandResolver: MCPServerCommandResolver())
    }

    init(fileSystem: FileSystem, serverCommandResolver: MCPServerCommandResolving) {
        self.fileSystem = fileSystem
        self.serverCommandResolver = serverCommandResolver
    }

    func update(at configPath: AbsolutePath) async throws {
        if !(try await fileSystem.exists(configPath.parentDirectory, isDirectory: true)) {
            try await fileSystem.makeDirectory(at: configPath.parentDirectory)
        }

        let existingContents = if try await fileSystem.exists(configPath) {
            try await fileSystem.readTextFile(at: configPath)
        } else {
            ""
        }

        let (command, args) = serverCommandResolver.resolve()
        let updatedContents = Self.updatingTuistMCPServer(
            in: existingContents,
            command: command,
            args: args
        )

        try Data(updatedContents.utf8).write(to: configPath.url, options: .atomic)
    }

    private static func updatingTuistMCPServer(in contents: String, command: String, args: [String]) -> String {
        let normalizedContents = contents.replacingOccurrences(of: "\r\n", with: "\n")
        let desiredSection = tuistMCPServerSection(command: command, args: args)

        if normalizedContents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return desiredSection
        }

        var lines = normalizedContents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let headerIndex = lines.firstIndex(where: isTuistMCPServersHeaderLine) {
            let endIndex = lines[(headerIndex + 1)...]
                .firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") }) ?? lines.count

            let sectionLines = Array(lines[(headerIndex + 1)..<endIndex])
            let updatedSectionLines = updatedSectionLines(
                from: sectionLines,
                command: command,
                args: args
            )

            lines.replaceSubrange((headerIndex + 1)..<endIndex, with: updatedSectionLines)

            return ensureTrailingNewline(lines.joined(separator: "\n"))
        } else {
            var updated = ensureTrailingNewline(normalizedContents)

            if !updated.hasSuffix("\n\n") {
                updated += "\n"
            }

            updated += desiredSection
            return ensureTrailingNewline(updated)
        }
    }

    private static func updatedSectionLines(from sectionLines: [String], command: String, args: [String]) -> [String] {
        var leadingLines: [String] = []
        var index = 0
        while index < sectionLines.count {
            let trimmed = sectionLines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                leadingLines.append(sectionLines[index])
                index += 1
            } else {
                break
            }
        }

        let remainingLines = Array(sectionLines[index...])
        let preservedLines = remainingLines.filter { line in
            !(matchesKeyAssignment(line: line, key: "command") || matchesKeyAssignment(line: line, key: "args"))
        }

        let commandLine = #"command = \#(tomlString(command))"#
        let argsLine = #"args = [\#(args.map(tomlString).joined(separator: ", "))]"#

        return leadingLines + [commandLine, argsLine] + preservedLines
    }

    private static func isTuistMCPServersHeaderLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed == "[mcp_servers.tuist]" || trimmed == #"[mcp_servers."tuist"]"# || trimmed == #"[mcp_servers.'tuist']"#
    }

    private static func matchesKeyAssignment(line: String, key: String) -> Bool {
        let trimmedLeading = line.drop { $0 == " " || $0 == "\t" }
        guard trimmedLeading.hasPrefix(key) else { return false }

        let remainder = trimmedLeading.dropFirst(key.count)
        let afterWhitespace = remainder.drop { $0 == " " || $0 == "\t" }
        return afterWhitespace.first == "="
    }

    private static func tuistMCPServerSection(command: String, args: [String]) -> String {
        let commandLine = #"command = \#(tomlString(command))"#
        let argsLine = #"args = [\#(args.map(tomlString).joined(separator: ", "))]"#
        return ensureTrailingNewline(
            [
                "[mcp_servers.tuist]",
                commandLine,
                argsLine,
            ].joined(separator: "\n")
        )
    }

    private static func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func ensureTrailingNewline(_ value: String) -> String {
        value.hasSuffix("\n") ? value : value + "\n"
    }
}

