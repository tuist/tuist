import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistLoader
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

struct BundleShowServiceTests {
    private var getBundleService: MockGetBundleServicing!
    private var subject: BundleShowService!
    private var configLoader: MockConfigLoading!
    private var serverURL: URL!
    private var serverAuthenticationController: MockServerAuthenticationControlling!

    init() {
        getBundleService = .init()
        configLoader = MockConfigLoading()
        serverURL = URL(string: "https://test.tuist.dev")!
        serverAuthenticationController = MockServerAuthenticationControlling()
        given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))
        given(serverAuthenticationController).authenticationToken(serverURL: .any).willReturn(.user(
            legacyToken: "token",
            accessToken: nil,
            refreshToken: nil
        ))

        subject = BundleShowService(
            getBundleService: getBundleService,
            serverEnvironmentService: ServerEnvironmentService(),
            configLoader: configLoader
        )
    }

    @Test func bundle_show_with_details() async throws {
        // Given
        let bundle = ServerBundle.test()
//        let bundle = ServerBundle.test(
//            id: "bundle-123",
//            name: "MyApp-iOS-arm64",
//            bundleVersion: Version(major: 1, minor: 2, patch: 3),
//            platforms: [.iOS, .iPadOS],
//            githubPRNumber: 456,
//            size: 250_000,
//            gitBranch: "feature/new-feature",
//            gitCommit: "abc123def456",
//            releaseDate: Date(timeIntervalSince1970: 1_700_000_000),
//            artifacts: [
//                ServerBundleArtifact(
//                    bundleType: .framework,
//                    path: "MyFramework.xcframework",
//                    size: 150_000,
//                    shasum: "sha256:abc123",
//                    children: [
//                        ServerBundleArtifact(
//                            bundleType: .framework,
//                            path: "ios-arm64",
//                            size: 75_000,
//                            shasum: "sha256:def456",
//                            children: []
//                        ),
//                        ServerBundleArtifact(
//                            bundleType: .framework,
//                            path: "ios-arm64_x86_64-simulator",
//                            size: 75_000,
//                            shasum: "sha256:ghi789",
//                            children: []
//                        ),
//                    ]
//                ),
//            ]
//        )
//
        given(getBundleService)
            .getBundle(fullHandle: .value("tuist/test"), bundleId: .value("bundle-123"), serverURL: .value(serverURL))
            .willReturn(bundle)

        // When
        try await subject.run(
            fullHandle: "tuist/test",
            bundleId: "bundle-123",
            path: nil,
            json: false
        )

        // Then
//        let output = try #require(TuistSupport.printer.outputBuffer)
//        try #require(output).contains("Bundle Details:")
//        try #require(output).contains("ID: bundle-123")
//        try #require(output).contains("Name: MyApp-iOS-arm64")
//        try #require(output).contains("Version: 1.2.3")
//        try #require(output).contains("Platforms: iOS, iPadOS")
//        try #require(output).contains("PR Number: 456")
//        try #require(output).contains("Branch: feature/new-feature")
//        try #require(output).contains("Commit: abc123def456")
//        try #require(output).contains("Size: 250.0 KB")
//        try #require(output).contains("Artifacts:")
//        try #require(output).contains("  • MyFramework.xcframework (framework) - 150.0 KB - sha256:abc123")
//        try #require(output).contains("    • ios-arm64 (framework) - 75.0 KB - sha256:def456")
//        try #require(output).contains("    • ios-arm64_x86_64-simulator (framework) - 75.0 KB - sha256:ghi789")
    }

//    @Test(.withMockedDependencies) func bundle_show_json_output() async throws {
//        // Given
//        let bundle = ServerBundle.test(
//            id: "bundle-123",
//            name: "MyApp-iOS-arm64",
//            bundleVersion: Version(major: 1, minor: 2, patch: 3),
//            platforms: [.iOS],
//            size: 250_000
//        )
//
//        given(getBundleService)
//            .getBundle(fullHandle: .value("tuist/test"), bundleId: .value("bundle-123"), serverURL: .value(serverURL))
//            .willReturn(bundle)
//
//        // When
//        try await subject.run(
//            fullHandle: "tuist/test",
//            bundleId: "bundle-123",
//            path: nil,
//            json: true
//        )
//
//        // Then
//        let output = try #require(TuistSupport.printer.outputBuffer)
//        try #require(output).contains("\"id\" : \"bundle-123\"")
//        try #require(output).contains("\"name\" : \"MyApp-iOS-arm64\"")
//        try #require(output).contains("\"bundleVersion\" : \"1.2.3\"")
//        try #require(output).contains("\"platforms\" : [")
//        try #require(output).contains("\"iOS\"")
//        try #require(output).contains("\"size\" : 250000")
//    }
//
//    @Test(.withMockedDependencies) func bundle_show_minimal_details() async throws {
//        // Given
//        let bundle = ServerBundle.test(
//            id: "bundle-123",
//            name: "MyApp",
//            bundleVersion: Version(major: 1, minor: 0, patch: 0),
//            platforms: [.macOS],
//            githubPRNumber: nil,
//            size: 100_000,
//            gitBranch: nil,
//            gitCommit: nil,
//            releaseDate: nil,
//            artifacts: []
//        )
//
//        given(getBundleService)
//            .getBundle(fullHandle: .value("tuist/test"), bundleId: .value("bundle-123"), serverURL: .value(serverURL))
//            .willReturn(bundle)
//
//        // When
//        try await subject.run(
//            fullHandle: "tuist/test",
//            bundleId: "bundle-123",
//            path: nil,
//            json: false
//        )
//
//        // Then
//        let output = try #require(TuistSupport.printer.outputBuffer)
//        try #require(output).contains("Bundle Details:")
//        try #require(output).contains("ID: bundle-123")
//        try #require(output).contains("Name: MyApp")
//        try #require(output).contains("Version: 1.0.0")
//        try #require(output).contains("Platforms: macOS")
//        try #require(output).contains("Size: 100.0 KB")
//        try #require(output).contains("No artifacts found")
//    }
//
//    @Test(.withMockedDependencies) func bundle_show_with_error() async throws {
//        // Given
//        given(getBundleService)
//            .getBundle(fullHandle: .value("tuist/test"), bundleId: .value("bundle-123"), serverURL: .value(serverURL))
//            .willThrow(BundleShowServiceError.missingFullHandle)
//
//        // When/Then
//        await #expect(throws: BundleShowServiceError.missingFullHandle) {
//            try await subject.run(
//                fullHandle: "tuist/test",
//                bundleId: "bundle-123",
//                path: nil,
//                json: false
//            )
//        }
//    }
//
//    @Test(.withMockedDependencies, .inTemporaryDirectory) func bundle_show_with_project_in_directory() async throws {
//        // Given
//        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
//        let projectPath = temporaryDirectory.appending(components: "Project.swift")
//        try await FileSystem.shared.write(projectPath, Data())
//
//        given(configLoader).loadConfig(path: .value(temporaryDirectory)).willReturn(.test(url: serverURL, project: "organization/project"))
//
//        let bundle = ServerBundle.test(
//            id: "bundle-123",
//            name: "MyApp-iOS",
//            bundleVersion: Version(major: 1, minor: 0, patch: 0),
//            platforms: [.iOS]
//        )
//
//        given(getBundleService)
//            .getBundle(fullHandle: .value("organization/project"), bundleId: .value("bundle-123"), serverURL: .value(serverURL))
//            .willReturn(bundle)
//
//        // When
//        try await subject.run(
//            fullHandle: nil,
//            bundleId: "bundle-123",
//            path: temporaryDirectory.pathString,
//            json: false
//        )
//
//        // Then
//        let output = try #require(TuistSupport.printer.outputBuffer)
//        try #require(output).contains("Bundle Details:")
//        try #require(output).contains("ID: bundle-123")
//        try #require(output).contains("Name: MyApp-iOS")
//    }
}
