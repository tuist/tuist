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

// struct BundleListServiceTests {
//    private var listBundlesService: MockListBundlesServicing!
//    private var subject: BundleListService!
//    private var configLoader: MockConfigLoading!
//    private var serverURL: URL!
//    private var serverAuthenticationController: MockServerAuthenticationControlling!
//
//    init() {
//        listBundlesService = .init()
//        configLoader = MockConfigLoading()
//        serverURL = URL(string: "https://test.tuist.dev")!
//        serverAuthenticationController = MockServerAuthenticationControlling()
//        given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))
//        given(serverAuthenticationController).authenticationToken(serverURL: .any).willReturn(.user(legacyToken: "token", accessToken: nil, refreshToken: nil))
//
//        subject = BundleListService(
//            listBundlesService: listBundlesService,
//            configLoader: configLoader,
//            serverAuthenticationController: serverAuthenticationController
//        )
//    }
//
//    @Test(.withMockedDependencies) func bundle_list_with_bundles() async throws {
//        // Given
//        given(listBundlesService)
//            .listBundles(fullHandle: .value("tuist/test"), serverURL: .value(serverURL))
//            .willReturn(
//                [
//                    .test(
//                        id: "1",
//                        name: "MyApp-macOS-x86_64",
//                        bundleVersion: Version(major: 1, minor: 0, patch: 0),
//                        platforms: [.macOS],
//                        githubPRNumber: 123,
//                        size: 100_000
//                    ),
//                    .test(
//                        id: "2",
//                        name: "MyApp-iOS-arm64",
//                        bundleVersion: Version(major: 1, minor: 0, patch: 1),
//                        platforms: [.iOS],
//                        size: 150_000
//                    ),
//                ]
//            )
//
//        // When
//        try await subject.run(
//            fullHandle: "tuist/test",
//            path: nil,
//            gitBranch: nil,
//            json: false
//        )
//
//        // Then
//        try #require(TuistSupport.printer.outputBuffer).contains("""
//        Listing bundles in project tuist/test...
//          • MyApp-macOS-x86_64 (1.0.0) - macOS - PR #123 - 100.0 KB
//          • MyApp-iOS-arm64 (1.0.1) - iOS - 150.0 KB
//        """)
//    }
//
//    @Test(.withMockedDependencies) func bundle_list_json_output() async throws {
//        // Given
//        given(listBundlesService)
//            .listBundles(fullHandle: .value("tuist/test"), serverURL: .value(serverURL))
//            .willReturn(
//                [
//                    .test(
//                        id: "1",
//                        name: "MyApp-macOS-x86_64",
//                        bundleVersion: Version(major: 1, minor: 0, patch: 0),
//                        platforms: [.macOS],
//                        size: 100_000
//                    ),
//                ]
//            )
//
//        // When
//        try await subject.run(
//            fullHandle: "tuist/test",
//            path: nil,
//            gitBranch: nil,
//            json: true
//        )
//
//        // Then
//        let output = try #require(TuistSupport.printer.outputBuffer)
//        try #require(output).contains("\"id\" : \"1\"")
//        try #require(output).contains("\"name\" : \"MyApp-macOS-x86_64\"")
//        try #require(output).contains("\"bundleVersion\" : \"1.0.0\"")
//        try #require(output).contains("\"platforms\" : [")
//        try #require(output).contains("\"macOS\"")
//        try #require(output).contains("\"size\" : 100000")
//    }
//
//    @Test(.withMockedDependencies) func bundle_list_when_none() async throws {
//        // Given
//        given(listBundlesService)
//            .listBundles(fullHandle: .value("tuist/test"), serverURL: .value(serverURL))
//            .willReturn([])
//
//        // When
//        try await subject.run(
//            fullHandle: "tuist/test",
//            path: nil,
//            gitBranch: nil,
//            json: false
//        )
//
//        // Then
//        try #require(TuistSupport.printer.outputBuffer).contains(
//            "No bundles found for project tuist/test"
//        )
//    }
//
//    @Test(.withMockedDependencies) func bundle_list_with_error() async throws {
//        // Given
//        given(listBundlesService)
//            .listBundles(fullHandle: .value("tuist/test"), serverURL: .value(serverURL))
//            .willThrow(BundleListServiceError.missingFullHandle)
//
//        // When/Then
//        await #expect(throws: BundleListServiceError.missingFullHandle) {
//            try await subject.run(
//                fullHandle: "tuist/test",
//                path: nil,
//                gitBranch: nil,
//                json: false
//            )
//        }
//    }
//
//    @Test(.withMockedDependencies, .inTemporaryDirectory) func bundle_list_with_project_in_directory() async throws {
//        // Given
//        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
//        let projectPath = temporaryDirectory.appending(components: "Project.swift")
//        try await FileSystem.shared.write(projectPath, Data())
//
//        given(configLoader).loadConfig(path: .value(temporaryDirectory)).willReturn(.test(url: serverURL, project: "organization/project"))
//        given(listBundlesService)
//            .listBundles(fullHandle: .value("organization/project"), serverURL: .value(serverURL))
//            .willReturn(
//                [
//                    .test(
//                        id: "1",
//                        name: "MyApp-iOS",
//                        bundleVersion: Version(major: 1, minor: 0, patch: 0),
//                        platforms: [.iOS]
//                    ),
//                ]
//            )
//
//        // When
//        try await subject.run(
//            fullHandle: nil,
//            path: temporaryDirectory.pathString,
//            gitBranch: nil,
//            json: false
//        )
//
//        // Then
//        try #require(TuistSupport.printer.outputBuffer).contains("""
//        Listing bundles in project organization/project...
//          • MyApp-iOS (1.0.0) - iOS
//        """)
//    }
// }
