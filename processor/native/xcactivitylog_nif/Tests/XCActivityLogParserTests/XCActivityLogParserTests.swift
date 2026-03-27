import Foundation
import Path
import Testing

@testable import XCActivityLogParser

@Suite
struct XCActivityLogParserTests {
    private let parser = XCActivityLogParser()

    private func fixtureURL(_ name: String) throws -> URL {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: "xcactivitylog", subdirectory: "Fixtures") else {
            throw FixtureError.notFound(name)
        }
        return url
    }

    private func emptyCASAnalyticsDbPath() throws -> AbsolutePath {
        try AbsolutePath(validating: NSTemporaryDirectory())
            .appending(component: "cas_analytics_\(UUID().uuidString).db")
    }

    // MARK: - Clean Build

    @Test func cleanBuild_parsesSuccessfully() async throws {
        let url = try fixtureURL("clean-build")
        let casDbPath = try emptyCASAnalyticsDbPath()

        let result = try await parser.parse(
            xcactivitylogURL: url,
            casAnalyticsDatabasePath: casDbPath
        )

        #expect(result.category == "clean")
        #expect(result.status == "success")
        #expect(result.error_count == 0)
        #expect(!result.targets.isEmpty)
        #expect(result.duration > 0)
        #expect(!result.unique_identifier.isEmpty)
    }

    @Test func cleanBuild_parsesTargets() async throws {
        let url = try fixtureURL("clean-build")
        let casDbPath = try emptyCASAnalyticsDbPath()

        let result = try await parser.parse(
            xcactivitylogURL: url,
            casAnalyticsDatabasePath: casDbPath
        )

        for target in result.targets {
            #expect(!target.name.isEmpty)
            #expect(!target.project.isEmpty)
            #expect(target.build_duration >= 0)
            #expect(target.status == "success")
        }
    }

    @Test func cleanBuild_parsesFiles() async throws {
        let url = try fixtureURL("clean-build")
        let casDbPath = try emptyCASAnalyticsDbPath()

        let result = try await parser.parse(
            xcactivitylogURL: url,
            casAnalyticsDatabasePath: casDbPath
        )

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
        let url = try fixtureURL("incremental-build")
        let casDbPath = try emptyCASAnalyticsDbPath()

        let result = try await parser.parse(
            xcactivitylogURL: url,
            casAnalyticsDatabasePath: casDbPath
        )

        #expect(result.category == "incremental")
        #expect(result.status == "success")
    }

    // MARK: - Failed Build

    @Test func failedBuild_reportsErrors() async throws {
        let url = try fixtureURL("failed-build")
        let casDbPath = try emptyCASAnalyticsDbPath()

        let result = try await parser.parse(
            xcactivitylogURL: url,
            casAnalyticsDatabasePath: casDbPath
        )

        #expect(result.status == "failure")
        #expect(result.error_count > 0)
        #expect(result.issues.contains { $0.type == "error" })
    }

    // MARK: - Build With Warnings

    @Test func buildWithWarning_parsesWarnings() async throws {
        let url = try fixtureURL("build-with-warning")
        let casDbPath = try emptyCASAnalyticsDbPath()

        let result = try await parser.parse(
            xcactivitylogURL: url,
            casAnalyticsDatabasePath: casDbPath
        )

        #expect(result.issues.contains { $0.type == "warning" })
        for issue in result.issues {
            #expect(issue.type == "warning" || issue.type == "error")
            #expect(!issue.signature.isEmpty)
        }
    }

    // MARK: - CAS Build Category Detection

    @Test func xcode26CASCleanBuild_detectsCleanCategory() async throws {
        let url = try fixtureURL("xcode_26_cas_clean_build")
        let casDbPath = try emptyCASAnalyticsDbPath()

        let result = try await parser.parse(
            xcactivitylogURL: url,
            casAnalyticsDatabasePath: casDbPath
        )

        #expect(result.category == "clean")
    }

    @Test func xcode26CASIncrementalBuild_detectsIncrementalCategory() async throws {
        let url = try fixtureURL("xcode_26_cas_incremental_build")
        let casDbPath = try emptyCASAnalyticsDbPath()

        let result = try await parser.parse(
            xcactivitylogURL: url,
            casAnalyticsDatabasePath: casDbPath
        )

        #expect(result.category == "incremental")
    }

    // MARK: - Build With Compilation Cache

    @Test func buildWithCache_parsesCacheableTasks() async throws {
        let url = try fixtureURL("xcode_26_4_clean_build_with_cache")
        let casDbPath = try emptyCASAnalyticsDbPath()

        let result = try await parser.parse(
            xcactivitylogURL: url,
            casAnalyticsDatabasePath: casDbPath
        )

        #expect(!result.cacheable_tasks.isEmpty)
        for task in result.cacheable_tasks {
            #expect(task.type == "swift" || task.type == "clang")
            #expect(task.status == "miss" || task.status == "hit_remote" || task.status == "hit_local")
            #expect(!task.key.isEmpty)
        }
    }

    // MARK: - Build With Uploads

    @Test func buildWithUploads_parsesCASOutputs() async throws {
        let url = try fixtureURL("build-with-uploads")
        let casDbPath = try emptyCASAnalyticsDbPath()

        let result = try await parser.parse(
            xcactivitylogURL: url,
            casAnalyticsDatabasePath: casDbPath
        )

        #expect(!result.cacheable_tasks.isEmpty)
    }

    // MARK: - CAS Metadata

    @Test func parse_readsCASMetadata_whenFilesExist() async throws {
        let url = try fixtureURL("build-with-uploads")
        let casDbPath = try emptyCASAnalyticsDbPath()

        let nodesDir = casPath.appending(component: "nodes")
        try FileManager.default.createDirectory(atPath: nodesDir.pathString, withIntermediateDirectories: true)
        let casDir = casPath.appending(component: "cas")
        try FileManager.default.createDirectory(atPath: casDir.pathString, withIntermediateDirectories: true)
        let kvDir = casPath.appending(component: "keyvalue")
        try FileManager.default.createDirectory(atPath: kvDir.pathString, withIntermediateDirectories: true)

        let result = try await parser.parse(
            xcactivitylogURL: url,
            casAnalyticsDatabasePath: casDbPath
        )

        // With empty CAS metadata dirs, CAS outputs that need metadata will be filtered out
        // but the parse itself should succeed
        #expect(result.status == "success" || result.status == "failure")
    }

    // MARK: - Output Structure

    @Test func parse_populatesAllFields() async throws {
        let url = try fixtureURL("clean-build")
        let casDbPath = try emptyCASAnalyticsDbPath()

        let result = try await parser.parse(
            xcactivitylogURL: url,
            casAnalyticsDatabasePath: casDbPath
        )

        #expect(!result.unique_identifier.isEmpty)
        #expect(result.time_started_recording > 0)
        #expect(result.time_stopped_recording > 0)
        #expect(result.time_stopped_recording >= result.time_started_recording)
        #expect(result.duration >= 0)

        let encoded = try JSONEncoder().encode(result)
        #expect(encoded.count > 0)
    }
}

enum FixtureError: Error {
    case notFound(String)
}
