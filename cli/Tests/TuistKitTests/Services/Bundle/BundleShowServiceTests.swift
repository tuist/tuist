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
            accessToken: .test(token: "access-token"),
            refreshToken: .test(token: "refresh-token")
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
    }
}
