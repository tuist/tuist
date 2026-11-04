import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistEnvironment
import TuistProcess
@testable import TuistGit
@testable import TuistTesting

/// Coverage-based test selection reads the diff between the baseline and the checkout from git,
/// so these run against real repositories rather than stubbed output.
struct GitControllerTestImpactTests {
    @Test(.inTemporaryDirectory) func changedFiles_lists_what_the_commits_changed_since_the_baseline() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let repository = try await makeRepository(at: path)
        try write("money v1", to: "Core/Money.swift", in: repository)
        try write("discount v1", to: "Core/Discount.swift", in: repository)
        try write("models v1", to: "Core/Models.swift", in: repository)
        let baseline = try commit("baseline", in: repository)
        try write("money v2", to: "Core/Money.swift", in: repository)
        try write("search v1", to: "Catalog/Search.swift", in: repository)
        try git(["rm", "-q", "Core/Models.swift"], in: repository)
        _ = try commit("change", in: repository)

        let result = try await GitController().changedFiles(
            workingDirectory: repository, since: baseline, deepening: [], limits: GitHistoryLimits()
        )

        #expect(result == .changed(GitChangedFiles(
            files: [
                GitChangedFile(path: "Catalog/Search.swift", status: "A", blobId: try blob("search v1")),
                GitChangedFile(path: "Core/Models.swift", status: "D", blobId: nil),
                GitChangedFile(path: "Core/Money.swift", status: "M", blobId: try blob("money v2")),
            ],
            dirty: false
        )))
    }

    @Test(.inTemporaryDirectory) func changedFiles_adds_dirty_and_untracked_files_against_the_baseline() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let repository = try await makeRepository(at: path)
        try write("money v1", to: "Core/Money.swift", in: repository)
        try write("discount v1", to: "Core/Discount.swift", in: repository)
        try write("models v1", to: "Core/Models.swift", in: repository)
        try write("notes v1", to: "docs/notes.md", in: repository)
        let baseline = try commit("baseline", in: repository)
        try write("money v2", to: "Core/Money.swift", in: repository)
        _ = try commit("change", in: repository)
        // The working tree reverts the committed change, edits another file, stages a third and
        // deletes a fourth.
        try write("money v1", to: "Core/Money.swift", in: repository)
        try write("discount v2", to: "Core/Discount.swift", in: repository)
        try write("notes v2", to: "docs/notes.md", in: repository)
        try git(["add", "docs/notes.md"], in: repository)
        try FileManager.default.removeItem(atPath: repository.appending(components: "Core", "Models.swift").pathString)
        try write("featured v1", to: "Catalog/Featured.swift", in: repository)
        try write("ignored", to: "build/output.o", in: repository)
        try write("build/\n", to: ".gitignore", in: repository)

        let result = try await GitController().changedFiles(
            workingDirectory: repository, since: baseline, deepening: [], limits: GitHistoryLimits()
        )

        #expect(result == .changed(GitChangedFiles(
            files: [
                GitChangedFile(path: ".gitignore", status: "A", blobId: try blob("build/\n")),
                GitChangedFile(path: "Catalog/Featured.swift", status: "A", blobId: try blob("featured v1")),
                GitChangedFile(path: "Core/Discount.swift", status: "M", blobId: try blob("discount v2")),
                GitChangedFile(path: "Core/Models.swift", status: "D", blobId: nil),
                GitChangedFile(path: "docs/notes.md", status: "M", blobId: try blob("notes v2")),
            ],
            dirty: true
        )))
    }

    @Test(.inTemporaryDirectory) func changedFiles_deepens_a_shallow_clone_to_the_baseline() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let origin = try await makeRepository(at: path.appending(component: "origin"))
        try write("money v1", to: "Core/Money.swift", in: origin)
        let baseline = try commit("baseline", in: origin)
        for index in 1 ... 60 {
            try write("money v\(index + 1)", to: "Core/Money.swift", in: origin)
            _ = try commit("change \(index)", in: origin)
        }
        let clone = path.appending(component: "clone")
        try git(["clone", "-q", "--depth=1", "--branch=main", "file://\(origin.pathString)", clone.pathString], in: path)

        let result = try await GitController().changedFiles(
            workingDirectory: clone, since: baseline, deepening: ["main"], limits: GitHistoryLimits(deepenBudgetSeconds: 30)
        )

        #expect(result == .changed(GitChangedFiles(
            files: [GitChangedFile(path: "Core/Money.swift", status: "M", blobId: try blob("money v61"))],
            dirty: false
        )))
    }

    @Test(.inTemporaryDirectory) func changedFiles_deepens_only_once() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let origin = try await makeRepository(at: path.appending(component: "origin"))
        try write("money v1", to: "Core/Money.swift", in: origin)
        let baseline = try commit("baseline", in: origin)
        for index in 1 ... 120 {
            try write("money v\(index + 1)", to: "Core/Money.swift", in: origin)
            _ = try commit("change \(index)", in: origin)
        }
        let clone = path.appending(component: "clone")
        try git(["clone", "-q", "--depth=1", "--branch=main", "file://\(origin.pathString)", clone.pathString], in: path)

        let result = try await GitController().changedFiles(
            workingDirectory: clone, since: baseline, deepening: ["main"], limits: GitHistoryLimits(deepenBudgetSeconds: 30)
        )

        #expect(result == .historyUnavailable(
            "shallow clone: the baseline \(baseline.prefix(12)) is more than 100 commits beyond the checkout"
        ))
        #expect(try git(["rev-list", "--count", "HEAD"], in: clone) == "101")
    }

    @Test(.inTemporaryDirectory) func deepenShallowClone_fetches_100_more_commits() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let origin = try await makeRepository(at: path.appending(component: "origin"))
        for index in 0 ... 120 {
            try write("money v\(index)", to: "Core/Money.swift", in: origin)
            _ = try commit("change \(index)", in: origin)
        }
        let clone = path.appending(component: "clone")
        try git(["clone", "-q", "--depth=1", "--branch=main", "file://\(origin.pathString)", clone.pathString], in: path)

        let deepened = await GitController().deepenShallowClone(
            workingDirectory: clone,
            refs: ["main"],
            limits: GitHistoryLimits()
        )
        let deepenedFullClone = await GitController().deepenShallowClone(
            workingDirectory: origin, refs: ["main"], limits: GitHistoryLimits()
        )

        #expect(deepened)
        #expect(try git(["rev-list", "--count", "HEAD"], in: clone) == "101")
        #expect(!deepenedFullClone)
    }

    @Test(.inTemporaryDirectory) func changedFiles_never_reaches_the_remote_without_a_ref_to_deepen() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let origin = try await makeRepository(at: path.appending(component: "origin"))
        try write("money v1", to: "Core/Money.swift", in: origin)
        let baseline = try commit("baseline", in: origin)
        try write("money v2", to: "Core/Money.swift", in: origin)
        _ = try commit("change", in: origin)
        let clone = path.appending(component: "clone")
        try git(["clone", "-q", "--depth=1", "--branch=main", "file://\(origin.pathString)", clone.pathString], in: path)

        let result = try await GitController().changedFiles(
            workingDirectory: clone, since: baseline, deepening: [], limits: GitHistoryLimits()
        )

        #expect(result == .historyUnavailable("shallow clone: the baseline \(baseline.prefix(12)) is not in the checkout"))
    }

    @Test(.inTemporaryDirectory) func changedFiles_reports_a_baseline_a_full_clone_lacks() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let repository = try await makeRepository(at: path)
        try write("money v1", to: "Core/Money.swift", in: repository)
        _ = try commit("baseline", in: repository)
        let unknown = String(repeating: "a", count: 40)

        let result = try await GitController().changedFiles(
            workingDirectory: repository, since: unknown, deepening: ["main"], limits: GitHistoryLimits()
        )

        #expect(result == .historyUnavailable("the baseline aaaaaaaaaaaa is not in the checkout's history"))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func checkedOutCommit_reads_a_pull_request_merge_commits_parents_in_a_depth_one_clone() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let origin = try await makeRepository(at: path.appending(component: "origin"))
        try write("money v1", to: "Core/Money.swift", in: origin)
        _ = try commit("baseline", in: origin)
        try git(["checkout", "-q", "-b", "feature"], in: origin)
        try write("discount v1", to: "Core/Discount.swift", in: origin)
        let pullRequestHead = try commit("feature", in: origin)
        try git(["checkout", "-q", "main"], in: origin)
        try write("catalog v1", to: "Catalog/Catalog.swift", in: origin)
        let baseTip = try commit("main", in: origin)
        try git(["merge", "-q", "--no-ff", "-m", "merge", "feature"], in: origin)
        let mergeCommit = try git(["rev-parse", "HEAD"], in: origin)
        let clone = path.appending(component: "clone")
        try git(["clone", "-q", "--depth=1", "--branch=main", "file://\(origin.pathString)", clone.pathString], in: path)
        try #require(Environment.mocked).variables = gitEnvironment.merging([
            "GITHUB_REF": "refs/pull/1/merge",
            "GITHUB_SHA": mergeCommit,
        ]) { _, new in new }

        let checkedOut = try await GitController(commandRunner: CommandRunner()).checkedOutCommit(workingDirectory: clone)

        #expect(checkedOut == GitCheckedOutCommit(
            sha: mergeCommit,
            parentSHAs: [baseTip, pullRequestHead],
            isPullRequestMerge: true
        ))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func checkedOutCommit_reads_the_parents_outside_a_pull_request_merge_checkout() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let repository = try await makeRepository(at: path)
        try write("money v1", to: "Core/Money.swift", in: repository)
        _ = try commit("baseline", in: repository)
        try git(["checkout", "-q", "-b", "feature"], in: repository)
        try write("discount v1", to: "Core/Discount.swift", in: repository)
        _ = try commit("feature", in: repository)
        try git(["checkout", "-q", "main"], in: repository)
        try git(["merge", "-q", "--no-ff", "-m", "merge", "feature"], in: repository)
        let head = try git(["rev-parse", "HEAD"], in: repository)
        let parents = try git(["rev-parse", "HEAD^1", "HEAD^2"], in: repository).split(separator: "\n").map(String.init)
        // A workflow that checked out another commit than GitHub's merge commit.
        try #require(Environment.mocked).variables = gitEnvironment.merging([
            "GITHUB_REF": "refs/pull/1/merge",
            "GITHUB_SHA": String(repeating: "b", count: 40),
        ]) { _, new in new }

        let checkedOut = try await GitController(commandRunner: CommandRunner()).checkedOutCommit(workingDirectory: repository)

        #expect(checkedOut == GitCheckedOutCommit(sha: head, parentSHAs: parents))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func checkedOutCommit_reads_a_new_commits_parent() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let repository = try await makeRepository(at: path)
        try write("money v1", to: "Core/Money.swift", in: repository)
        let parent = try commit("baseline", in: repository)
        try write("money v2", to: "Core/Money.swift", in: repository)
        let head = try commit("change", in: repository)
        try #require(Environment.mocked).variables = gitEnvironment

        let checkedOut = try await GitController(commandRunner: CommandRunner()).checkedOutCommit(workingDirectory: repository)

        #expect(checkedOut == GitCheckedOutCommit(sha: head, parentSHAs: [parent]))
    }

    @Test func parseRawDiff_reads_statuses_and_blobs() {
        let zero = String(repeating: "0", count: 40)
        let output = [
            ":100644 100644 aaa bbb M", "Core/Money.swift",
            ":000000 100644 \(zero) ccc A", "Catalog/Search.swift",
            ":100644 000000 ddd \(zero) D", "Core/Models.swift",
            ":100644 100644 eee \(zero) M", "with\ttab and space.swift",
        ].joined(separator: "\0") + "\0"

        #expect(GitHistoryParser.parseRawDiff(output) == [
            .init(path: "Core/Money.swift", status: "M", srcBlob: "aaa", dstBlob: "bbb"),
            .init(path: "Catalog/Search.swift", status: "A", srcBlob: nil, dstBlob: "ccc"),
            .init(path: "Core/Models.swift", status: "D", srcBlob: "ddd", dstBlob: nil),
            .init(path: "with\ttab and space.swift", status: "M", srcBlob: "eee", dstBlob: nil),
        ])
    }

    // MARK: - Helpers

    /// Commits need an identity, and the user's configuration (signing, hooks) must not apply.
    private var gitEnvironment: [String: String] {
        [
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Tuist",
            "GIT_AUTHOR_EMAIL": "tests@tuist.dev",
            "GIT_COMMITTER_NAME": "Tuist",
            "GIT_COMMITTER_EMAIL": "tests@tuist.dev",
        ]
    }

    private func makeRepository(at path: AbsolutePath) async throws -> AbsolutePath {
        try await FileSystem().makeDirectory(at: path)
        try git(["init", "-q", "--initial-branch=main"], in: path)
        try git(["config", "uploadpack.allowFilter", "true"], in: path)
        return path
    }

    private func write(_ contents: String, to relativePath: String, in repository: AbsolutePath) throws {
        let path = try repository.appending(RelativePath(validating: relativePath))
        try FileManager.default.createDirectory(atPath: path.parentDirectory.pathString, withIntermediateDirectories: true)
        try contents.write(toFile: path.pathString, atomically: true, encoding: .utf8)
    }

    private func commit(_ message: String, in repository: AbsolutePath) throws -> String {
        try git(["add", "-A"], in: repository)
        try git(["commit", "-q", "-m", message], in: repository)
        return try git(["rev-parse", "HEAD"], in: repository)
    }

    private func blob(_ contents: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "hash-object", "--stdin"]
        process.environment = gitEnvironment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(Data(contents.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    private func git(_ arguments: [String], in directory: AbsolutePath) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory.pathString] + arguments
        process.environment = gitEnvironment
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitTestError.failed(arguments.joined(separator: " "))
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum GitTestError: Error {
        case failed(String)
    }
}
