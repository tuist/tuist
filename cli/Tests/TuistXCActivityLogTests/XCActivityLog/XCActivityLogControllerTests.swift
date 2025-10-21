import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistSupport

@testable import TuistTesting
@testable import TuistXCActivityLog

struct XCActivityLogControllerTests {
    private let fileSystem = FileSystem()
    private let subject: XCActivityLogController

    init() throws {
        subject = try XCActivityLogController(
            fileSystem: fileSystem,
            environment: MockEnvironment()
        )
    }

    @Test func buildTimesByTarget() async throws {
        // Given
        let projectDerivedDataDirectory = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../../Fixtures/FrameworkDerivedDataWithActivityLog"))

        // When
        let got = try await subject.buildTimesByTarget(projectDerivedDataDirectory: projectDerivedDataDirectory)

        // Then
        #expect(got == ["Framework": 4.696011543273926])
    }

    @Test func parseCleanBuildXCActivityLog() async throws {
        // Given
        let cleanBuildXCActivityLog = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../../Fixtures/clean-build.xcactivitylog"))

        // When
        let got = try await subject.parse(cleanBuildXCActivityLog)

        // Then
        #expect(got.category == .clean)
    }

    @Test func parseBuildWithWarningXCActivityLog() async throws {
        // Given
        let buildWithWarningXCActivityLog = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../../Fixtures/build-with-warning.xcactivitylog"))

        // When
        let got = try await subject.parse(buildWithWarningXCActivityLog)

        // Then
        #expect(got.buildStep.errorCount == 0)
        #expect(got.issues.map(\.type) == [.warning, .warning])
    }

    @Test func parseIncrementalBuildXCActivityLog() async throws {
        // Given
        let incrementalBuildXCActivityLog = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../../Fixtures/incremental-build.xcactivitylog"))

        // When
        let got = try await subject.parse(incrementalBuildXCActivityLog)

        // Then
        #expect(got.category == .incremental)
    }

    @Test func parseFailedBuildXCActivityLog() async throws {
        // Given
        let xcactivityLog = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../../Fixtures/failed-build.xcactivitylog"))

        // When
        let got = try await subject.parse(xcactivityLog)

        // Then
        #expect(got.issues.map(\.type) == [.error])
        let issue = try #require(got.issues.first)
        #expect(issue.target == "Framework1")
        #expect(issue.project == "MainApp")
        #expect(issue.title == "Compile Framework1File.swift (arm64)")
        let files = got.files.sorted(by: { $0.path.pathString < $1.path.pathString })
        #expect(
            files.map(\.path.basename).contains("Framework1File.swift") == true
        )
        let targets = got.targets.sorted(by: { $0.name < $1.name })
        #expect(targets.map(\.name) == ["Framework1", "Framework2-iOS", "Framework3", "Framework4", "Framework5"])
        #expect(targets.map(\.status) == [.failure, .success, .success, .success, .success])
    }

    @Test(.inTemporaryDirectory)
    func mostRecentActivityLogFile_returnsNil_whenLogStoreManifestDoesNotExist() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectDerivedDataDirectory = temporaryDirectory.appending(component: "DerivedData")

        // When
        let result = try await subject.mostRecentActivityLogFile(
            projectDerivedDataDirectory: projectDerivedDataDirectory
        )

        // Then
        #expect(result == nil)
    }

    @Test(.inTemporaryDirectory)
    func mostRecentActivityLogFile_returnsMostRecentLog_whenMultipleLogsExist() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectDerivedDataDirectory = temporaryDirectory.appending(component: "DerivedData")
        let buildLogsDirectory = projectDerivedDataDirectory.appending(components: "Logs", "Build")

        try await fileSystem.makeDirectory(at: buildLogsDirectory)

        let manifestContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>logFormatVersion</key>
            <integer>11</integer>
            <key>logs</key>
            <dict>
                <key>log1-id</key>
                <dict>
                    <key>fileName</key>
                    <string>log1-id.xcactivitylog</string>
                    <key>timeStartedRecording</key>
                    <real>768154244.5</real>
                    <key>timeStoppedRecording</key>
                    <real>768154245.0</real>
                    <key>signature</key>
                    <string>Building project App with scheme App</string>
                </dict>
                <key>log2-id</key>
                <dict>
                    <key>fileName</key>
                    <string>log2-id.xcactivitylog</string>
                    <key>timeStartedRecording</key>
                    <real>768154245.5</real>
                    <key>timeStoppedRecording</key>
                    <real>768154246.0</real>
                    <key>signature</key>
                    <string>Building project App with scheme App</string>
                </dict>
                <key>log3-id</key>
                <dict>
                    <key>fileName</key>
                    <string>log3-id.xcactivitylog</string>
                    <key>timeStartedRecording</key>
                    <real>768154243.5</real>
                    <key>timeStoppedRecording</key>
                    <real>768154244.0</real>
                    <key>signature</key>
                    <string>Building project App with scheme App</string>
                </dict>
            </dict>
        </dict>
        </plist>
        """

        let manifestPath = buildLogsDirectory.appending(component: "LogStoreManifest.plist")
        try await fileSystem.writeText(manifestContent, at: manifestPath)

        try await fileSystem.touch(buildLogsDirectory.appending(component: "log1-id.xcactivitylog"))
        try await fileSystem.touch(buildLogsDirectory.appending(component: "log2-id.xcactivitylog"))
        try await fileSystem.touch(buildLogsDirectory.appending(component: "log3-id.xcactivitylog"))

        // When
        let result = try await subject.mostRecentActivityLogFile(
            projectDerivedDataDirectory: projectDerivedDataDirectory
        )

        // Then
        let expectedResult = try #require(result)
        #expect(expectedResult.path.basename == "log2-id.xcactivitylog")
        #expect(expectedResult.signature == "Building project App with scheme App")
        #expect(expectedResult.timeStoppedRecording == Date(timeIntervalSinceReferenceDate: 768_154_246.0))
    }

    @Test(.inTemporaryDirectory)
    func mostRecentActivityLogFile_appliesFilter_whenFilterProvided() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectDerivedDataDirectory = temporaryDirectory.appending(component: "DerivedData")
        let buildLogsDirectory = projectDerivedDataDirectory.appending(components: "Logs", "Build")

        try await fileSystem.makeDirectory(at: buildLogsDirectory)

        let manifestContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>logFormatVersion</key>
            <integer>11</integer>
            <key>logs</key>
            <dict>
                <key>test-log-id</key>
                <dict>
                    <key>fileName</key>
                    <string>test-log-id.xcactivitylog</string>
                    <key>timeStartedRecording</key>
                    <real>768154245.5</real>
                    <key>timeStoppedRecording</key>
                    <real>768154246.0</real>
                    <key>signature</key>
                    <string>Testing project App with scheme App</string>
                </dict>
                <key>build-log-id</key>
                <dict>
                    <key>fileName</key>
                    <string>build-log-id.xcactivitylog</string>
                    <key>timeStartedRecording</key>
                    <real>768154244.5</real>
                    <key>timeStoppedRecording</key>
                    <real>768154245.0</real>
                    <key>signature</key>
                    <string>Building project App with scheme App</string>
                </dict>
            </dict>
        </dict>
        </plist>
        """

        let manifestPath = buildLogsDirectory.appending(component: "LogStoreManifest.plist")
        try await fileSystem.writeText(manifestContent, at: manifestPath)

        try await fileSystem.touch(buildLogsDirectory.appending(component: "test-log-id.xcactivitylog"))
        try await fileSystem.touch(buildLogsDirectory.appending(component: "build-log-id.xcactivitylog"))

        // When
        let result = try await subject.mostRecentActivityLogFile(
            projectDerivedDataDirectory: projectDerivedDataDirectory,
            filter: { $0.signature.contains("Building") }
        )

        // Then
        let expectedResult = try #require(result)
        #expect(expectedResult.path.basename == "build-log-id.xcactivitylog")
        #expect(expectedResult.signature == "Building project App with scheme App")
    }

    @Test(.inTemporaryDirectory)
    func mostRecentActivityLogFile_returnsNil_whenNoLogsMatchFilter() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectDerivedDataDirectory = temporaryDirectory.appending(component: "DerivedData")
        let buildLogsDirectory = projectDerivedDataDirectory.appending(components: "Logs", "Build")

        try await fileSystem.makeDirectory(at: buildLogsDirectory)

        let manifestContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>logFormatVersion</key>
            <integer>11</integer>
            <key>logs</key>
            <dict>
                <key>test-log-id</key>
                <dict>
                    <key>fileName</key>
                    <string>test-log-id.xcactivitylog</string>
                    <key>timeStartedRecording</key>
                    <real>768154245.5</real>
                    <key>timeStoppedRecording</key>
                    <real>768154246.0</real>
                    <key>signature</key>
                    <string>Testing project App with scheme App</string>
                </dict>
            </dict>
        </dict>
        </plist>
        """

        let manifestPath = buildLogsDirectory.appending(component: "LogStoreManifest.plist")
        try await fileSystem.writeText(manifestContent, at: manifestPath)

        try await fileSystem.touch(buildLogsDirectory.appending(component: "test-log-id.xcactivitylog"))

        // When
        let result = try await subject.mostRecentActivityLogFile(
            projectDerivedDataDirectory: projectDerivedDataDirectory,
            filter: { $0.signature.contains("Building") }
        )

        // Then
        #expect(result == nil)
    }

    @Test(.inTemporaryDirectory)
    func mostRecentActivityLogFile_returnsSingleLog_whenOnlyOneLogExists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectDerivedDataDirectory = temporaryDirectory.appending(component: "DerivedData")
        let buildLogsDirectory = projectDerivedDataDirectory.appending(components: "Logs", "Build")

        try await fileSystem.makeDirectory(at: buildLogsDirectory)

        let manifestContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>logFormatVersion</key>
            <integer>11</integer>
            <key>logs</key>
            <dict>
                <key>single-log-id</key>
                <dict>
                    <key>fileName</key>
                    <string>single-log-id.xcactivitylog</string>
                    <key>timeStartedRecording</key>
                    <real>768154246.0</real>
                    <key>timeStoppedRecording</key>
                    <real>768154246.5</real>
                    <key>signature</key>
                    <string>Building project Framework with scheme Framework</string>
                </dict>
            </dict>
        </dict>
        </plist>
        """

        let manifestPath = buildLogsDirectory.appending(component: "LogStoreManifest.plist")
        try await fileSystem.writeText(manifestContent, at: manifestPath)

        try await fileSystem.touch(buildLogsDirectory.appending(component: "single-log-id.xcactivitylog"))

        // When
        let result = try await subject.mostRecentActivityLogFile(
            projectDerivedDataDirectory: projectDerivedDataDirectory
        )

        // Then
        let expectedResult = try #require(result)
        #expect(expectedResult.path.basename == "single-log-id.xcactivitylog")
        #expect(expectedResult.signature == "Building project Framework with scheme Framework")
        #expect(expectedResult.timeStoppedRecording == Date(timeIntervalSinceReferenceDate: 768_154_246.5))
    }
}
