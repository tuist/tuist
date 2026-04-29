import FileSystem
import Foundation
import Path
import Testing
import XCLogParser

@testable import XCActivityLogParser

@Suite
struct XCActivityLogParserTests {
    private let parser = XCActivityLogParser()
    private let fileSystem = FileSystem()

    private func fixtureURL(_ name: String) throws -> URL {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: "xcactivitylog", subdirectory: "Fixtures") else {
            throw FixtureError.notFound(name)
        }
        return url
    }

    private func parseFixture(_ name: String) async throws -> BuildData {
        let url = try fixtureURL(name)
        return try await fileSystem.runInTemporaryDirectory(prefix: "xcactivitylog-test") { tempDir in
            try await parser.parse(
                xcactivitylogURL: url,
                casAnalyticsDatabasePath: tempDir.appending(component: "cas_analytics.db")
            )
        }
    }

    // MARK: - Clean Build

    @Test func cleanBuild_parsesSuccessfully() async throws {
        let result = try await parseFixture("clean-build")

        #expect(result.category == "clean")
        #expect(result.status == "success")
        #expect(result.error_count == 0)
        #expect(!result.targets.isEmpty)
        #expect(result.duration > 0)
        #expect(!result.unique_identifier.isEmpty)
    }

    @Test func cleanBuild_parsesTargets() async throws {
        let result = try await parseFixture("clean-build")

        for target in result.targets {
            #expect(!target.name.isEmpty)
            #expect(!target.project.isEmpty)
            #expect(target.build_duration >= 0)
            #expect(target.compilation_duration >= 0)
            #expect(target.status == "success")
        }
    }

    @Test func cleanBuild_parsesFiles() async throws {
        let result = try await parseFixture("clean-build")

        #expect(!result.files.isEmpty)
        for file in result.files {
            #expect(file.type == "swift" || file.type == "c")
            #expect(!file.path.isEmpty)
            #expect(!file.target.isEmpty)
            #expect(file.compilation_duration >= 0)
        }
    }

    // MARK: - Incremental Build

    @Test func incrementalBuild_detectsIncrementalCategory() async throws {
        let result = try await parseFixture("incremental-build")

        #expect(result.category == "incremental")
        #expect(result.status == "success")
    }

    // MARK: - Failed Build

    @Test func failedBuild_reportsErrors() async throws {
        let result = try await parseFixture("failed-build")

        #expect(result.status == "failure")
        #expect(result.error_count > 0)
        #expect(result.issues.contains { $0.type == "error" })
    }

    // MARK: - Build With Warnings

    @Test func buildWithWarning_parsesWarnings() async throws {
        let result = try await parseFixture("build-with-warning")

        #expect(result.issues.contains { $0.type == "warning" })
        for issue in result.issues {
            #expect(issue.type == "warning" || issue.type == "error")
            #expect(!issue.signature.isEmpty)
        }
    }

    // MARK: - CAS Build Category Detection

    @Test func xcode26CASCleanBuild_detectsCleanCategory() async throws {
        let result = try await parseFixture("xcode_26_cas_clean_build")
        #expect(result.category == "clean")
    }

    @Test func xcode26CASIncrementalBuild_detectsIncrementalCategory() async throws {
        let result = try await parseFixture("xcode_26_cas_incremental_build")
        #expect(result.category == "incremental")
    }

    // MARK: - Build With Compilation Cache

    @Test func buildWithCache_parsesCacheableTasks() async throws {
        let result = try await parseFixture("xcode_26_4_clean_build_with_cache")

        #expect(!result.cacheable_tasks.isEmpty)
        for task in result.cacheable_tasks {
            #expect(task.type == "swift" || task.type == "clang")
            #expect(task.status == "miss" || task.status == "hit_remote" || task.status == "hit_local")
            #expect(!task.key.isEmpty)
        }
    }

    // MARK: - Full Parse

    @Test func parse_populatesAllFields() async throws {
        let result = try await parseFixture("clean-build")

        #expect(!result.unique_identifier.isEmpty)
        #expect(result.duration > 0)
        #expect(result.time_started_recording > 0)
        #expect(result.time_stopped_recording > 0)
        #expect(result.version > 0)
    }

    // MARK: - Build With Uploads

    @Test func buildWithUploads_parsesUploads() async throws {
        let result = try await parseFixture("build-with-uploads")

        #expect(result.status == "success")
    }

    @Test func buildWithUploads_doesNotClassifyUploadOnlyKeysAsHitLocal() async throws {
        let result = try await parseFixture("build-with-uploads")

        // A key observed only in `Swift caching upload key ...` — i.e. written to the remote
        // CAS without a matching materialize/query step — is a fresh compilation that had to
        // run and push its result. That is a miss, not a local-CAS hit.
        for task in result.cacheable_tasks where task.write_duration != nil {
            #expect(task.status != "hit_local",
                    "Upload-bearing key \(task.key) misclassified as hit_local")
        }
    }

    // MARK: - flattenBuildSteps

    @Test func flattenBuildSteps_handlesDeepTreeWithoutStackOverflow() {
        // Recursive flatten blew the stack on deeply nested step trees; the
        // iterative DFS shouldn't. 2000 is well past the recursive Swift
        // limit on a default test thread (~1k frames) but low enough that
        // tearing the nested struct down via ARC at scope exit doesn't itself
        // overflow the stack — the latter is unrelated to what we're testing.
        let depth = 2_000
        var leaf = makeStep(identifier: "step-\(depth)", subSteps: [])
        for level in stride(from: depth - 1, through: 0, by: -1) {
            leaf = makeStep(identifier: "step-\(level)", subSteps: [leaf])
        }

        let result = parser.flattenBuildSteps([leaf])

        #expect(result.count == depth + 1)
        #expect(result.first?.identifier == "step-0")
        #expect(result.last?.identifier == "step-\(depth)")
    }

    @Test func flattenBuildSteps_preservesDFSOrder() {
        // Two siblings at the root, each with two children — DFS pre-order
        // is: a, a1, a2, b, b1, b2.
        let tree = [
            makeStep(identifier: "a", subSteps: [
                makeStep(identifier: "a1", subSteps: []),
                makeStep(identifier: "a2", subSteps: [])
            ]),
            makeStep(identifier: "b", subSteps: [
                makeStep(identifier: "b1", subSteps: []),
                makeStep(identifier: "b2", subSteps: [])
            ])
        ]

        let result = parser.flattenBuildSteps(tree)

        #expect(result.map(\.identifier) == ["a", "a1", "a2", "b", "b1", "b2"])
    }

    private func makeStep(identifier: String, subSteps: [BuildStep]) -> BuildStep {
        BuildStep(
            type: .detail,
            machineName: "",
            buildIdentifier: "",
            identifier: identifier,
            parentIdentifier: "",
            domain: "",
            title: "",
            signature: "",
            startDate: "",
            endDate: "",
            startTimestamp: 0,
            endTimestamp: 0,
            duration: 0,
            detailStepType: .other,
            buildStatus: "",
            schema: "",
            subSteps: subSteps,
            warningCount: 0,
            errorCount: 0,
            architecture: "",
            documentURL: "",
            warnings: nil,
            errors: nil,
            notes: nil,
            swiftFunctionTimes: nil,
            fetchedFromCache: false,
            compilationEndTimestamp: 0,
            compilationDuration: 0,
            clangTimeTraceFile: nil,
            linkerStatistics: nil,
            swiftTypeCheckTimes: nil
        )
    }
}

enum FixtureError: Error {
    case notFound(String)
}
