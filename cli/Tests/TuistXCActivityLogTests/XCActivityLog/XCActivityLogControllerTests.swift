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
        subject = XCActivityLogController(
            fileSystem: fileSystem
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

    @Test func xcode_26_2() async throws {
        // Given
        let incrementalBuildXCActivityLog = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../../Fixtures/xcode_26_2.xcactivitylog"))

        // When
        let got = try await subject.parse(incrementalBuildXCActivityLog)

        // Then
        #expect(got.category == .clean)
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

    @Test(.withMockedEnvironment())
    func parseFailedBuildXCActivityLogWithMissesAndRemoteHits() async throws {
        // Given
        let xcactivityLog = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../../Fixtures/failed-build-with-cache-misses.xcactivitylog"))
        let environment = try #require(Environment.mocked)
        environment.cacheDirectory = xcactivityLog.parentDirectory.appending(component: "cache")

        // When
        let got = try await subject.parse(xcactivityLog)

        // Then
        #expect(got.cacheableTasks.count == 60)
        #expect(got.cacheableTasks.filter { $0.type == .swift }.count == 60)
        #expect(got.cacheableTasks.filter { $0.status == .localHit }.count == 0)
        #expect(got.cacheableTasks.filter { $0.status == .remoteHit }.count == 56)
        #expect(got.cacheableTasks.filter { $0.status == .miss }.count == 4)
        #expect(got.cacheableTasks.first(where: { $0.description == "Emitting module for App" })?
            .key == "0~2mxgYt89XELBx7Yle2QsoK_eC5ZW-zz7c2IzKlQ4FeelsLoqKbnPfM1Q9VyYsasx6L_wBw2KmcwklmaOhsUARw=="
        )
    }

    @Test(.withMockedEnvironment())
    func parseBuildXCActivityLogWithRemoteHits() async throws {
        // Given
        let xcactivityLog = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../../Fixtures/build-with-remote-hits/build-with-remote-hits.xcactivitylog"))
        let environment = try #require(Environment.mocked)
        environment.stateDirectory = xcactivityLog.parentDirectory.appending(component: "state")

        // When
        let got = try await subject.parse(xcactivityLog)

        // Then
        #expect(got.cacheableTasks.count == 4)
        #expect(got.cacheableTasks.filter { $0.type == .swift }.count == 4)
        #expect(got.cacheableTasks.filter { $0.status == .remoteHit }.count == 4)
        #expect(got.casOutputs.sorted(by: { $0.checksum > $1.checksum }) == [
            CASOutput(
                nodeID: "0~49C6atHfmLcVaRO9lWE7wi7It4d3XXldCc6LDXAC1aWAP-QrpArK3FmZCo0AfkqQ2s8Iv849KKmGuzfXPHL39Q==",
                checksum: "FB2B7F87083C8A254241BBF8252BA6CD6D6F0C9092A111F4C7D28A3B4B90D4BB",
                size: 58816,
                duration: 62.71795835345984,
                compressedSize: 17474,
                operation: .download,
                type: .object
            ),
            CASOutput(
                nodeID: "0~qeHr278TkWv-ycmH7r4g5Qpttl9k2OSZizeDRQ_uvdOI1neASwjp_tr-fyGJpDzpnTWYnaeXAOfvxVzWSRtb6w==",
                checksum: "1AA11EDE9E7D361F00311116278DB5D504862C5361177CA7DB948CA6BE9F8200",
                size: 360,
                duration: 60.29745831619948,
                compressedSize: 239,
                operation: .download,
                type: .localizationStrings
            ),
            CASOutput(
                nodeID: "0~WEQaHKJTHxk9lH2TjUnA35KCw98xCj0YZtedxm9Pcr8tJgZUptlaFMEML50DYq0ZNsecu6K-aRW_BeQtqEX-uA==",
                checksum: "061F37DBA51A251AB6DCC00BB34E25985A41F6FFDB599E2CBD6825AA8F2F5EF7",
                size: 3468,
                duration: 62.295541632920504,
                compressedSize: 1457,
                operation: .download,
                type: .swiftSourceInfoFile
            ),
        ])
        #expect(got.cacheableTasks.map(\.nodeIDs).flatMap { $0 }.count == 25)
    }

    @Test(.withMockedEnvironment())
    func parseBuildXCActivityLogWithUploads() async throws {
        // Given
        let xcactivityLog = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../../Fixtures/build-with-uploads/build-with-uploads.xcactivitylog"))
        let environment = try #require(Environment.mocked)
        environment.stateDirectory = xcactivityLog.parentDirectory.appending(component: "state")

        // When
        let got = try await subject.parse(xcactivityLog)

        // Then
        #expect(got.cacheableTasks.count == 2)
        #expect(got.cacheableTasks.filter { $0.type == .swift }.count == 2)
        #expect(got.cacheableTasks.filter { $0.status == .miss }.count == 2)
        #expect(got.casOutputs.filter { $0.operation == .upload }.count == 9)
        #expect(got.cacheableTasks.sorted(by: { $0.key > $1.key }).map(\.readDuration) == [96.02287504822016, 98.0583333875984])
        #expect(got.cacheableTasks.sorted(by: { $0.key > $1.key }).map(\.writeDuration) == [
            106.85816663317382,
            111.20187502820045,
        ])
        #expect(got.cacheableTasks.map(\.nodeIDs).flatMap { $0 }.count == 13)
    }

    @Test(.withMockedEnvironment())
    func parseBuildXCActivityLogWithLocalHits() async throws {
        // Given
        let xcactivityLog = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../../Fixtures/build-with-local-hits.xcactivitylog"))

        // When
        let got = try await subject.parse(xcactivityLog)

        // Then
        #expect(got.cacheableTasks.count == 4)
        #expect(got.cacheableTasks.filter { $0.type == .swift }.count == 4)
        #expect(got.cacheableTasks.filter { $0.status == .localHit }.count == 4)
        #expect(got.cacheableTasks.filter { $0.status == .remoteHit }.count == 0)
        #expect(got.cacheableTasks.filter { $0.status == .miss }.count == 0)
    }
}
