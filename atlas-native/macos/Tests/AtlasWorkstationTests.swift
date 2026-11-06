import Darwin
import Foundation
import Testing

struct AtlasWorkstationTests {
    @Test func githubIdentityUsesOnlyLocalPublicGitHubRemotes() async throws {
        for remote in ["git@github.com:Acme/Monorepo.git", "https://github.com/Acme/Monorepo.git",
                       "ssh://git@github.com/Acme/Monorepo"] {
            #expect(AtlasWorkstationProjects.githubRepository(remote: remote) == "acme/monorepo")
        }
        for remote in ["https://token@github.com/acme/repo", "https://github.com.evil.test/acme/repo",
                       "file:///Users/person/repo", "git@gitlab.com:acme/repo.git",
                       "https://github.com/acme/repo?secret=value", "https://github.com/acme/repo/extra",
                       "https://github.com/acme/repo#branch", "git@github.com:acme/repo\n"] {
            #expect(AtlasWorkstationProjects.githubRepository(remote: remote) == nil)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let setup = await AtlasWorkstationExecution.perform(command("environment_terminal", source:
            "git init -q && git remote add origin git@github.com:Acme/Monorepo.git"), root: root)
        try #require(setup.success)
        let projects = await AtlasWorkstationProjects.metadata(["project-id": root])
        #expect(projects.count == 1)
        #expect(projects.first?.repository == "acme/monorepo")
        #expect(projects.first?.coding == true)
    }

    @Test func codingWorktreesIsolateDirtyCheckoutsAndSurviveReopening() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = base.appendingPathComponent("repository")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let setup = await AtlasWorkstationExecution.perform(command("environment_terminal", source:
            "git init -q && printf 'base\\nsecond\\nthird\\n' > file && git add file && " +
            "git -c user.name=Atlas -c user.email=test@example.invalid -c commit.gpgsign=false commit -qm initial"), root: root)
        try #require(setup.success)
        try Data("dirty original".utf8).write(to: root.appendingPathComponent("file"))
        let thread = UUID().uuidString.lowercased()
        let first = try AtlasWorkstationWorktrees.prepare(repository: root, directory: base.appendingPathComponent("first"),
                                                         threadId: thread, title: "Fix Unicode / handling")
        let second = try AtlasWorkstationWorktrees.prepare(repository: root, directory: base.appendingPathComponent("second"),
                                                          threadId: UUID().uuidString.lowercased(), title: "Fix Unicode / handling")
        let write = await AtlasWorkstationExecution.perform(coding("write", path: "file", content: "isolated edit"), root: first)
        #expect(write.success)
        #expect(try String(contentsOf: root.appendingPathComponent("file"), encoding: .utf8) == "dirty original")
        #expect(try String(contentsOf: second.appendingPathComponent("file"), encoding: .utf8) == "base\nsecond\nthird\n")
        let reopened = try AtlasWorkstationWorktrees.prepare(repository: root, directory: first, threadId: thread, title: "Another title")
        #expect(try String(contentsOf: reopened.appendingPathComponent("file"), encoding: .utf8) == "isolated edit")
        let branch = await AtlasWorkstationExecution.perform(command("environment_terminal", source: "git branch --show-current"), root: first)
        #expect(branch.output == "atlas/fix-unicode-handling-\(thread)\n")
        let read = await AtlasWorkstationExecution.perform(coding("read", path: "file", offset: 2, limit: 1), root: second)
        #expect(read.success && read.output == "2: second\n[Truncated. Continue with offset=3; for an oversized line use bash.]")
    }

    @Test func editsMatchOriginalTextAtomicallyAndPreserveUnicodeBOMAndCRLF() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file")
        let original = "\u{FEFF}one é\r\ntwo λ\r\nthree\r\n"
        try Data(original.utf8).write(to: file)
        let edited = await AtlasWorkstationExecution.perform(coding("edit", path: "file", edits: [
            .init(oldText: "two λ\nthree", newText: "changed\nend"), .init(oldText: "one é", newText: "first Ω")
        ]), root: root)
        #expect(edited.success)
        let expected = "\u{FEFF}first Ω\r\nchanged\r\nend\r\n"
        #expect(try Data(contentsOf: file) == Data(expected.utf8))
        for edits: [AtlasWorkstationCommand.Edit] in [
            [.init(oldText: "first Ω", newText: "partial"), .init(oldText: "missing", newText: "bad")],
            [.init(oldText: "changed\nend", newText: "bad"), .init(oldText: "end", newText: "overlap")],
            [.init(oldText: "\n", newText: "ambiguous")]
        ] {
            let failed = await AtlasWorkstationExecution.perform(coding("edit", path: "file", edits: edits), root: root)
            #expect(!failed.success)
            #expect(try Data(contentsOf: file) == Data(expected.utf8))
        }
        let outside = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try Data("outside".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        for path in ["escape", "../\(outside.lastPathComponent)", outside.path] {
            let denied = await AtlasWorkstationExecution.perform(coding("write", path: path, content: "bad"), root: root)
            #expect(!denied.success)
        }
        #expect(try String(contentsOf: outside, encoding: .utf8) == "outside")
        let empty = await AtlasWorkstationExecution.perform(coding("write", path: "empty", content: ""), root: root)
        #expect(empty.success)
        #expect(try Data(contentsOf: root.appendingPathComponent("empty")).isEmpty)
    }

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

    private func coding(_ tool: String, path: String, content: String? = nil,
                        offset: Int? = nil, limit: Int? = nil, edits: [AtlasWorkstationCommand.Edit]? = nil) -> AtlasWorkstationCommand {
        AtlasWorkstationCommand(id: UUID().uuidString.lowercased(), tool: tool,
                                arguments: .init(projectId: UUID().uuidString.lowercased(), path: path, command: nil,
                                                 offset: offset, limit: limit, content: content, edits: edits),
                                digest: String(repeating: "a", count: 64), claimToken: nil)
    }
}
