import Darwin
import Foundation
import Testing

struct AtlasWorkstationTests {
    @Test func fileToolsStayInsideTheProjectAndBoundDirectoryResults() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = base.appendingPathComponent("project")
        let sibling = base.appendingPathComponent("project-private")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try Data("Selected project".utf8).write(to: root.appendingPathComponent("readme.txt"))
        try Data("Outside secret".utf8).write(to: sibling.appendingPathComponent("secret.txt"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: sibling)
        let valid = await AtlasWorkstationExecution.perform(command("environment_read_file", path: "readme.txt"), root: root)
        #expect(valid.success && valid.output == "Selected project")
        for path in ["../project-private/secret.txt", "escape/secret.txt", sibling.appendingPathComponent("secret.txt").path] {
            let denied = await AtlasWorkstationExecution.perform(command("environment_read_file", path: path), root: root)
            #expect(!denied.success && !denied.output.contains("Outside secret"))
        }
        let denied = await AtlasWorkstationExecution.perform(command("environment_list_directory", path: "escape"), root: root)
        #expect(!denied.success && !denied.output.contains("secret.txt"))
        for index in 0..<105 { try Data().write(to: root.appendingPathComponent("entry-\(index)")) }
        let listed = await AtlasWorkstationExecution.perform(command("environment_list_directory", path: "."), root: root)
        try #require(listed.success)
        let result = try #require(JSONSerialization.jsonObject(with: Data(listed.output.utf8)) as? [String: Any])
        #expect((result["entries"] as? [[String: Any]])?.count == 100)
        #expect(result["truncated"] as? Bool == true)
    }

    @Test func terminalPreservesCommandTextExitStatusAndOutputLimits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let success = await AtlasWorkstationExecution.perform(
            command("environment_terminal", source: "printf '%s\\n' 'a; b $c'; /bin/pwd"), root: root
        )
        #expect(success.success)
        let lines = success.output.split(separator: "\n")
        try #require(lines.count == 2)
        #expect(lines[0] == "a; b $c")
        #expect(URL(fileURLWithPath: String(lines[1])).resolvingSymlinksInPath() == root.resolvingSymlinksInPath())
        let failed = await AtlasWorkstationExecution.perform(command("environment_terminal", source: "printf failed; exit 7"), root: root)
        #expect(!failed.success && failed.output == "failed")
        let bounded = await AtlasWorkstationExecution.perform(
            command("environment_terminal", source: "printf old-prefix; /usr/bin/yes 'é' | /usr/bin/head -n 20000; printf final-marker"),
            root: root
        )
        #expect(bounded.success)
        #expect(bounded.output.hasPrefix("[Earlier output omitted; showing the latest output.]"))
        #expect(!bounded.output.contains("old-prefix"))
        #expect(bounded.output.hasSuffix("final-marker"))
        #expect(bounded.output.utf8.count <= 48 * 1024)
        let binary = await AtlasWorkstationExecution.perform(
            command("environment_terminal", source: "printf '\\377'"), root: root
        )
        #expect(!binary.success && binary.output == "Command output was not UTF-8; binary output was not sent.")
    }

    @Test func terminalKeepsRunningPastThirtySecondsAndCanBeCancelledWithoutLosingProgress() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let progress = AtlasWorkstationProgress()
        let task = Task {
            await AtlasWorkstationExecution.perform(command("environment_terminal", source: "printf started; sleep 31; printf still-running; sleep 120"),
                                                   root: root, progress: progress)
        }
        defer { task.cancel() }
        let deadline = ContinuousClock.now + .seconds(40)
        while progress.text?.contains("still-running") != true, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(progress.text == "startedstill-running")
        task.cancel()
        let result = await task.value
        #expect(!result.success)
        #expect(result.output.contains("startedstill-running"))
        #expect(result.output.contains("Command stopped"))
    }

    private func command(_ tool: String, path: String? = nil, source: String? = nil) -> AtlasWorkstationCommand {
        AtlasWorkstationCommand(id: UUID().uuidString.lowercased(), tool: tool,
                                arguments: .init(projectId: UUID().uuidString.lowercased(), path: path, command: source),
                                digest: String(repeating: "a", count: 64), claimToken: nil)
    }
}
