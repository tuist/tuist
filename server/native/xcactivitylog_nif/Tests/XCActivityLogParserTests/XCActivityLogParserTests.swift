import FileSystem
import Foundation
import Path
import Testing

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

    @Test(arguments: ["clean-build", "incremental-build", "xcode_26_cas_incremental_build", "failed-build"])
    func buildSteps_usesOnlyIntervalsFromThisBuild(fixture: String) async throws {
        let result = try await parseFixture(fixture)
        #expect(!result.build_steps.isEmpty)
        #expect(Set(result.build_steps.map(\.event_id)).count == result.build_steps.count)
        let duration = (result.time_stopped_recording - result.time_started_recording) * 1000
        for event in result.build_steps {
            #expect(event.start_ms >= 0)
            #expect(event.duration_ms > 0)
            #expect(event.start_ms + event.duration_ms <= duration + 0.001)
        }
    }

    @Test func buildSteps_classifiesModernSwiftCompilation() async throws {
        let result = try await parseFixture("clean-build")
        #expect(result.build_steps.contains { $0.category == "swiftCompilation" && $0.target == "App" })
        #expect(result.build_steps.contains { $0.category == "swiftCompilation" && $0.title.hasPrefix("Emit Swift module") })
        #expect(result.build_steps.contains { $0.category == "scriptExecution" })
        #expect(!result.build_steps.contains { $0.title.hasPrefix("Build target ") })
    }

    @Test func buildSteps_retainsRecordedStepCommands() async throws {
        let result = try await parseFixture("xcode_26_cas_clean_build")
        let step = try #require(result.build_steps.first { $0.log.hasPrefix("EmitSwiftModule normal") })
        #expect(step.log.contains("EmitSwiftModule normal"))
        #expect(step.log.contains("cd "))
        #expect(!step.log_truncated)
    }

    @Test func buildSteps_logPreservesOutputAndBoundsUTF8() {
        let log = BuildStepLog.render(signature: "Compile App", command: "cd /workspace", output: "<warning>\nhello", messages: ["<warning>", "note"], limit: 1000)
        #expect(log.text == "Compile App\ncd /workspace\n<warning>\nhello\nnote")
        #expect(!log.truncated)
        let truncated = BuildStepLog.render(signature: "a🙂b", command: "", output: "", messages: [], limit: 4)
        #expect(truncated.text == "a")
        #expect(truncated.truncated)
        #expect(BuildStepLog.render(signature: "command", command: "", output: "", messages: [], limit: 0).truncated)
    }

    @Test func buildSteps_rejectsStaleAndInvalidIntervals() {
        #expect(BuildStepData.interval(start: 9, end: 11, buildStart: 10, buildEnd: 20) == nil)
        #expect(BuildStepData.interval(start: 11, end: 21, buildStart: 10, buildEnd: 20) == nil)
        #expect(BuildStepData.interval(start: 12, end: 11, buildStart: 10, buildEnd: 20) == nil)
        #expect(BuildStepData.interval(start: 12, end: 12, buildStart: 10, buildEnd: 20) == nil)
        #expect(BuildStepData.interval(start: .nan, end: 12, buildStart: 10, buildEnd: 20) == nil)
        let interval = BuildStepData.interval(start: 10.5, end: 12, buildStart: 10, buildEnd: 20)
        #expect(interval?.0 == 500)
        #expect(interval?.1 == 1500)
    }

    @Test func buildSteps_logNormalizesAndDeduplicatesBeforeTruncation() {
        let log = BuildStepLog.render(signature: "Compile App", command: "Compile App\r\ncd /workspace", output: "hello\rworld\r\n", messages: ["hello\nworld\n"], limit: 1000)
        #expect(log.text == "Compile App\ncd /workspace\nhello\nworld\n")
        #expect(!log.truncated)
        let exact = BuildStepLog.render(signature: "a\r\n", command: "", output: "", messages: [], limit: 2)
        #expect(exact.text == "a\n")
        #expect(!exact.truncated)
        let oversized = BuildStepLog.render(signature: "a", command: "a🙂", output: "", messages: [], limit: 4)
        #expect(oversized.text == "a")
        #expect(oversized.truncated)
    }

    @Test func buildSteps_logBoundsLargeOutput() {
        let output = String(repeating: "🙂\r\n", count: 4 * 1024 * 1024)
        let log = BuildStepLog.render(signature: "Compile", command: "", output: output, messages: ["end"], limit: 64 * 1024)
        #expect(log.text == "Compile\n" + String(repeating: "🙂\n", count: 13_105))
        #expect(log.text.utf8.count <= 64 * 1024)
        #expect(log.truncated)
        let exhausted = BuildStepLog.render(signature: "", command: "", output: output, messages: [], limit: 0)
        #expect(exhausted.text.isEmpty)
        #expect(exhausted.truncated)
    }

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

    @Test func xcode27FailedBuild_toleratesEndedStatusToken() async throws {
        let result = try await parseFixture("xcode_27_failed_build")

        #expect(result.status == "failure")
        #expect(result.error_count > 0)
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

    // MARK: - Local Cache Hit Notes
    //
    // `local-cache-hit-notes-only` and `local-cache-hit-notes-only-modules` are derived from
    // `xcode_26_cas_clean_build` and `xcode_26_4_clean_build_with_cache` by renaming the
    // `Swift caching ` step-title prefix so no key retains a query/materialize/upload step.
    // That reproduces a compilation replayed straight out of the local CAS, whose only trace
    // in the log is the note on the compile step. The modules fixture additionally flips its
    // cache-miss notes to their hit spelling to cover the lower-case clang/module form.

    @Test func localCacheHitNotes_areRecordedAsLocalHits() async throws {
        let result = try await parseFixture("local-cache-hit-notes-only")
        let noteKeys = try localCacheHitKeys(inFixture: "local-cache-hit-notes-only")

        #expect(noteKeys.capitalised.count == 6)
        #expect(noteKeys.lowercased.isEmpty)
        #expect(Set(result.cacheable_tasks.map(\.key)) == noteKeys.capitalised)
        for task in result.cacheable_tasks {
            #expect(task.status == "hit_local")
            #expect(task.type == "swift")
            #expect(task.read_duration == nil)
            #expect(task.write_duration == nil)
            #expect(task.description != nil)
        }
    }

    @Test func localCacheHitNotes_typeModuleNotesAsClang() async throws {
        let result = try await parseFixture("local-cache-hit-notes-only-modules")
        let noteKeys = try localCacheHitKeys(inFixture: "local-cache-hit-notes-only-modules")

        #expect(noteKeys.capitalised.count == 3)
        #expect(noteKeys.lowercased.count == 56)

        let byKey = Dictionary(uniqueKeysWithValues: result.cacheable_tasks.map { ($0.key, $0) })
        #expect(Set(byKey.keys) == noteKeys.capitalised.union(noteKeys.lowercased))
        #expect(result.cacheable_tasks.allSatisfy { $0.status == "hit_local" })
        #expect(noteKeys.capitalised.allSatisfy { byKey[$0]?.type == "swift" })
        #expect(noteKeys.lowercased.allSatisfy { byKey[$0]?.type == "clang" })
    }

    @Test func localCacheHitNotes_reconcileWithNoteCountForEveryCASFixture() async throws {
        for fixture in [
            "local-cache-hit-notes-only",
            "local-cache-hit-notes-only-modules",
            "xcode_26_cas_clean_build",
            "xcode_26_cas_incremental_build",
            "xcode_26_4_clean_build_with_cache",
            "build-with-uploads",
        ] {
            let result = try await parseFixture(fixture)
            let noteKeys = try localCacheHitKeys(inFixture: fixture)
            let localHits = result.cacheable_tasks.filter { $0.status == "hit_local" }

            #expect(Set(localHits.map(\.key)) == noteKeys.capitalised.union(noteKeys.lowercased),
                    "\(fixture): local hits do not match the log's local-cache-hit notes")
            #expect(Set(result.cacheable_tasks.map(\.key)).count == result.cacheable_tasks.count,
                    "\(fixture): a key was reported more than once")
        }
    }

    // Every note key in this fixture also has a `Swift caching materialize key` step, so the
    // note pass must not add a second task for it.
    @Test func localCacheHitNotes_doNotDuplicateKeysThatHaveCachingSteps() async throws {
        let result = try await parseFixture("xcode_26_cas_clean_build")

        #expect(result.cacheable_tasks.count == 6)
        #expect(Set(result.cacheable_tasks.map(\.key)).count == 6)
    }

    private func localCacheHitKeys(inFixture name: String) throws -> (capitalised: Set<String>, lowercased: Set<String>) {
        let log = String(decoding: try gunzip(try fixtureURL(name)), as: UTF8.self)
        func keys(_ pattern: String) throws -> Set<String> {
            let regex = try NSRegularExpression(pattern: pattern)
            let matches = regex.matches(in: log, range: NSRange(log.startIndex..., in: log))
            return Set(matches.compactMap { Range($0.range(at: 1), in: log).map { String(log[$0]) } })
        }
        let key = "(0~[A-Za-z0-9+/_-]+={0,2})"
        return (
            capitalised: try keys("Local cache found for key: \(key)"),
            lowercased: try keys("(?<![A-Za-z])local cache found for key: \(key)")
        )
    }

    private func gunzip(_ url: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-dc", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }
}

enum FixtureError: Error {
    case notFound(String)
}
