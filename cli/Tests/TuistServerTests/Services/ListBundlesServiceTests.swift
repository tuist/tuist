import Foundation
import Mockable
import Testing
import struct TSCUtility.Version
import TuistSupport
import TuistTesting

@testable import TuistServer

// struct ListBundlesServiceTests {
//    private var subject: ListBundlesService!
//    private var serverClient: MockServerClientServicing!
//    private var serverAuthenticationController: MockServerAuthenticationControlling!
//    private let serverURL = URL(string: "https://test.tuist.dev")!
//
//    init() {
//        serverClient = .init()
//        serverAuthenticationController = MockServerAuthenticationControlling()
//        subject = ListBundlesService(
//            serverClient: serverClient,
//            serverAuthenticationController: serverAuthenticationController
//        )
//    }
//
//    @Test(.withMockedDependencies) func list_bundles_success() async throws {
//        // Given
//        given(serverAuthenticationController)
//            .authenticationToken(serverURL: .value(serverURL))
//            .willReturn(.user(legacyToken: "token", accessToken: nil, refreshToken: nil))
//
//        let expectedBundles = [
//            ServerBundle.test(
//                id: "1",
//                name: "MyApp-iOS",
//                bundleVersion: Version(major: 1, minor: 0, patch: 0),
//                platforms: [.iOS],
//                size: 100_000
//            ),
//            ServerBundle.test(
//                id: "2",
//                name: "MyApp-macOS",
//                bundleVersion: Version(major: 1, minor: 0, patch: 1),
//                platforms: [.macOS],
//                size: 150_000
//            ),
//        ]
//
//        given(serverClient)
//            .listBundles(fullHandle: .value("tuist/test"), serverURL: .value(serverURL))
//            .willReturn(expectedBundles)
//
//        // When
//        let bundles = try await subject.listBundles(
//            fullHandle: "tuist/test",
//            serverURL: serverURL
//        )
//
//        // Then
//        #expect(bundles == expectedBundles)
//    }
//
//    @Test(.withMockedDependencies) func list_bundles_empty_result() async throws {
//        // Given
//        given(serverAuthenticationController)
//            .authenticationToken(serverURL: .value(serverURL))
//            .willReturn(.user(legacyToken: "token", accessToken: nil, refreshToken: nil))
//
//        given(serverClient)
//            .listBundles(fullHandle: .value("tuist/test"), serverURL: .value(serverURL))
//            .willReturn([])
//
//        // When
//        let bundles = try await subject.listBundles(
//            fullHandle: "tuist/test",
//            serverURL: serverURL
//        )
//
//        // Then
//        #expect(bundles.isEmpty)
//    }
//
//    @Test(.withMockedDependencies) func list_bundles_unauthorized_error() async throws {
//        // Given
//        given(serverAuthenticationController)
//            .authenticationToken(serverURL: .value(serverURL))
//            .willReturn(nil)
//
//        let expectedError = ListBundlesServiceError.unauthorized(serverURL)
//        given(serverClient)
//            .listBundles(fullHandle: .value("tuist/test"), serverURL: .value(serverURL))
//            .willThrow(expectedError)
//
//        // When/Then
//        await #expect(throws: ListBundlesServiceError.unauthorized(serverURL)) {
//            _ = try await subject.listBundles(
//                fullHandle: "tuist/test",
//                serverURL: serverURL
//            )
//        }
//    }
//
//    @Test(.withMockedDependencies) func list_bundles_forbidden_error() async throws {
//        // Given
//        given(serverAuthenticationController)
//            .authenticationToken(serverURL: .value(serverURL))
//            .willReturn(.user(legacyToken: "token", accessToken: nil, refreshToken: nil))
//
//        let expectedError = ListBundlesServiceError.forbidden("tuist/test", serverURL)
//        given(serverClient)
//            .listBundles(fullHandle: .value("tuist/test"), serverURL: .value(serverURL))
//            .willThrow(expectedError)
//
//        // When/Then
//        await #expect(throws: ListBundlesServiceError.forbidden("tuist/test", serverURL)) {
//            _ = try await subject.listBundles(
//                fullHandle: "tuist/test",
//                serverURL: serverURL
//            )
//        }
//    }
//
//    @Test(.withMockedDependencies) func list_bundles_not_found_error() async throws {
//        // Given
//        given(serverAuthenticationController)
//            .authenticationToken(serverURL: .value(serverURL))
//            .willReturn(.user(legacyToken: "token", accessToken: nil, refreshToken: nil))
//
//        let expectedError = ListBundlesServiceError.projectNotFound("tuist/test", serverURL)
//        given(serverClient)
//            .listBundles(fullHandle: .value("tuist/test"), serverURL: .value(serverURL))
//            .willThrow(expectedError)
//
//        // When/Then
//        await #expect(throws: ListBundlesServiceError.projectNotFound("tuist/test", serverURL)) {
//            _ = try await subject.listBundles(
//                fullHandle: "tuist/test",
//                serverURL: serverURL
//            )
//        }
//    }
//
//    @Test(.withMockedDependencies) func list_bundles_unknown_error() async throws {
//        // Given
//        given(serverAuthenticationController)
//            .authenticationToken(serverURL: .value(serverURL))
//            .willReturn(.user(legacyToken: "token", accessToken: nil, refreshToken: nil))
//
//        let expectedError = ListBundlesServiceError.unknownError(500)
//        given(serverClient)
//            .listBundles(fullHandle: .value("tuist/test"), serverURL: .value(serverURL))
//            .willThrow(expectedError)
//
//        // When/Then
//        await #expect(throws: ListBundlesServiceError.unknownError(500)) {
//            _ = try await subject.listBundles(
//                fullHandle: "tuist/test",
//                serverURL: serverURL
//            )
//        }
//    }
// }
