import Foundation
import Mockable
import Testing
import struct TSCUtility.Version
import TuistSupport
import TuistTesting

@testable import TuistServer

// struct GetBundleServiceTests {
//    private var subject: GetBundleService!
//    private var serverClient: MockServerClientServicing!
//    private var serverAuthenticationController: MockServerAuthenticationControlling!
//    private let serverURL = URL(string: "https://test.tuist.dev")!
//
//    init() {
//        serverClient = .init()
//        serverAuthenticationController = MockServerAuthenticationControlling()
//        subject = GetBundleService(
//            serverClient: serverClient,
//            serverAuthenticationController: serverAuthenticationController
//        )
//    }
//
//    @Test(.withMockedDependencies) func get_bundle_success() async throws {
//        // Given
//        given(serverAuthenticationController)
//            .authenticationToken(serverURL: .value(serverURL))
//            .willReturn(.user(legacyToken: "token", accessToken: nil, refreshToken: nil))
//
//        let expectedBundle = ServerBundle.test(
//            id: "bundle-123",
//            name: "MyApp-iOS-arm64",
//            bundleVersion: Version(major: 1, minor: 2, patch: 3),
//            platforms: [.iOS, .iPadOS],
//            githubPRNumber: 456,
//            size: 250_000,
//            gitBranch: "feature/new-feature",
//            gitCommit: "abc123def456",
//            releaseDate: Date(),
//            artifacts: [
//                ServerBundleArtifact(
//                    bundleType: .framework,
//                    path: "MyFramework.xcframework",
//                    size: 150_000,
//                    shasum: "sha256:abc123",
//                    children: []
//                ),
//            ]
//        )
//
//        given(serverClient)
//            .getBundle(fullHandle: .value("tuist/test"), bundleId: .value("bundle-123"), serverURL: .value(serverURL))
//            .willReturn(expectedBundle)
//
//        // When
//        let bundle = try await subject.getBundle(
//            fullHandle: "tuist/test",
//            bundleId: "bundle-123",
//            serverURL: serverURL
//        )
//
//        // Then
//        #expect(bundle == expectedBundle)
//    }
//
//    @Test(.withMockedDependencies) func get_bundle_with_nested_artifacts() async throws {
//        // Given
//        given(serverAuthenticationController)
//            .authenticationToken(serverURL: .value(serverURL))
//            .willReturn(.user(legacyToken: "token", accessToken: nil, refreshToken: nil))
//
//        let expectedBundle = ServerBundle.test(
//            id: "bundle-123",
//            name: "MyApp-Universal",
//            bundleVersion: Version(major: 2, minor: 0, patch: 0),
//            platforms: [.iOS, .macOS],
//            size: 500_000,
//            artifacts: [
//                ServerBundleArtifact(
//                    bundleType: .framework,
//                    path: "MyFramework.xcframework",
//                    size: 300_000,
//                    shasum: "sha256:parent",
//                    children: [
//                        ServerBundleArtifact(
//                            bundleType: .framework,
//                            path: "ios-arm64",
//                            size: 100_000,
//                            shasum: "sha256:child1",
//                            children: []
//                        ),
//                        ServerBundleArtifact(
//                            bundleType: .framework,
//                            path: "macos-arm64_x86_64",
//                            size: 200_000,
//                            shasum: "sha256:child2",
//                            children: []
//                        ),
//                    ]
//                ),
//            ]
//        )
//
//        given(serverClient)
//            .getBundle(fullHandle: .value("tuist/test"), bundleId: .value("bundle-123"), serverURL: .value(serverURL))
//            .willReturn(expectedBundle)
//
//        // When
//        let bundle = try await subject.getBundle(
//            fullHandle: "tuist/test",
//            bundleId: "bundle-123",
//            serverURL: serverURL
//        )
//
//        // Then
//        #expect(bundle.artifacts.count == 1)
//        #expect(bundle.artifacts[0].children.count == 2)
//    }
//
//    @Test(.withMockedDependencies) func get_bundle_unauthorized_error() async throws {
//        // Given
//        given(serverAuthenticationController)
//            .authenticationToken(serverURL: .value(serverURL))
//            .willReturn(nil)
//
//        let expectedError = GetBundleServiceError.unauthorized(serverURL)
//        given(serverClient)
//            .getBundle(fullHandle: .value("tuist/test"), bundleId: .value("bundle-123"), serverURL: .value(serverURL))
//            .willThrow(expectedError)
//
//        // When/Then
//        await #expect(throws: GetBundleServiceError.unauthorized(serverURL)) {
//            _ = try await subject.getBundle(
//                fullHandle: "tuist/test",
//                bundleId: "bundle-123",
//                serverURL: serverURL
//            )
//        }
//    }
//
//    @Test(.withMockedDependencies) func get_bundle_forbidden_error() async throws {
//        // Given
//        given(serverAuthenticationController)
//            .authenticationToken(serverURL: .value(serverURL))
//            .willReturn(.user(legacyToken: "token", accessToken: nil, refreshToken: nil))
//
//        let expectedError = GetBundleServiceError.forbidden("tuist/test", serverURL)
//        given(serverClient)
//            .getBundle(fullHandle: .value("tuist/test"), bundleId: .value("bundle-123"), serverURL: .value(serverURL))
//            .willThrow(expectedError)
//
//        // When/Then
//        await #expect(throws: GetBundleServiceError.forbidden("tuist/test", serverURL)) {
//            _ = try await subject.getBundle(
//                fullHandle: "tuist/test",
//                bundleId: "bundle-123",
//                serverURL: serverURL
//            )
//        }
//    }
//
//    @Test(.withMockedDependencies) func get_bundle_not_found_error() async throws {
//        // Given
//        given(serverAuthenticationController)
//            .authenticationToken(serverURL: .value(serverURL))
//            .willReturn(.user(legacyToken: "token", accessToken: nil, refreshToken: nil))
//
//        let expectedError = GetBundleServiceError.bundleNotFound("bundle-123", serverURL)
//        given(serverClient)
//            .getBundle(fullHandle: .value("tuist/test"), bundleId: .value("bundle-123"), serverURL: .value(serverURL))
//            .willThrow(expectedError)
//
//        // When/Then
//        await #expect(throws: GetBundleServiceError.bundleNotFound("bundle-123", serverURL)) {
//            _ = try await subject.getBundle(
//                fullHandle: "tuist/test",
//                bundleId: "bundle-123",
//                serverURL: serverURL
//            )
//        }
//    }
//
//    @Test(.withMockedDependencies) func get_bundle_project_not_found_error() async throws {
//        // Given
//        given(serverAuthenticationController)
//            .authenticationToken(serverURL: .value(serverURL))
//            .willReturn(.user(legacyToken: "token", accessToken: nil, refreshToken: nil))
//
//        let expectedError = GetBundleServiceError.projectNotFound("tuist/test", serverURL)
//        given(serverClient)
//            .getBundle(fullHandle: .value("tuist/test"), bundleId: .value("bundle-123"), serverURL: .value(serverURL))
//            .willThrow(expectedError)
//
//        // When/Then
//        await #expect(throws: GetBundleServiceError.projectNotFound("tuist/test", serverURL)) {
//            _ = try await subject.getBundle(
//                fullHandle: "tuist/test",
//                bundleId: "bundle-123",
//                serverURL: serverURL
//            )
//        }
//    }
//
//    @Test(.withMockedDependencies) func get_bundle_unknown_error() async throws {
//        // Given
//        given(serverAuthenticationController)
//            .authenticationToken(serverURL: .value(serverURL))
//            .willReturn(.user(legacyToken: "token", accessToken: nil, refreshToken: nil))
//
//        let expectedError = GetBundleServiceError.unknownError(500)
//        given(serverClient)
//            .getBundle(fullHandle: .value("tuist/test"), bundleId: .value("bundle-123"), serverURL: .value(serverURL))
//            .willThrow(expectedError)
//
//        // When/Then
//        await #expect(throws: GetBundleServiceError.unknownError(500)) {
//            _ = try await subject.getBundle(
//                fullHandle: "tuist/test",
//                bundleId: "bundle-123",
//                serverURL: serverURL
//            )
//        }
//    }
// }
