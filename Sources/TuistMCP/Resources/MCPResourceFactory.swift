import Command
import FileSystem
import MCPServer
import Mockable
import Path

@Mockable
protocol MCPResourceFactorying {
    func fetch() async throws -> [MCPInterface.Resource]
}

struct MCPResourceFactory: MCPResourceFactorying {
    let commandRunner = CommandRunner()

    func fetch() async throws -> [MCPInterface.Resource] {
        var resources: [MCPInterface.Resource] = [
            .init(uri: "tuist://test", name: "Test"),
        ]
        if let frontMostXcodeWindowResource = try await fetchFrontMostXcodeWindowResource() {
            resources.append(frontMostXcodeWindowResource)
        }
        return resources
    }

    private func fetchFrontMostXcodeWindowResource() async throws -> MCPInterface.Resource? {
        let osascript = """
        '
              tell application "Xcode"
                if it is running then
                  set projectFile to path of document 1
                  return POSIX path of projectFile
                end if
              end tell
        '
        """
        do {
            let frontMostXcodeProjectOrWorkspacePathString = try await commandRunner.run(arguments: [
                "/usr/bin/osascript",
                "-e",
                osascript,
            ]).concatenatedString(including: Set([.standardError, .standardOutput]))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard frontMostXcodeProjectOrWorkspacePathString != "",
                  let frontMostXcodeProjectOrWorkspacePath =
                  try? AbsolutePath(validating: frontMostXcodeProjectOrWorkspacePathString)
            else {
                return nil
            }
            return MCPInterface.Resource(
                uri: "tuist://graphs/\(frontMostXcodeProjectOrWorkspacePath.basenameWithoutExt)",
                name: frontMostXcodeProjectOrWorkspacePath.basenameWithoutExt,
                description: "Xcode project or workspace located at \(frontMostXcodeProjectOrWorkspacePathString)",
                mimeType: "application/json"
            )
        } catch {
            try await FileSystem().writeText(
                (error as? CustomStringConvertible)?.description ?? "",
                at: AbsolutePath(validating: "/Users/pepicrft/Downloads/test.txt")
            )
            return nil
        }
    }
}
