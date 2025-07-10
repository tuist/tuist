import Foundation
import Mockable
import TuistLoader
import TuistServer
import TuistTesting
import XCTest

@testable import TuistKit

final class BundleShowServiceTests: TuistUnitTestCase {
    private var getBundleService: MockGetBundleServicing!
    private var subject: BundleShowService!
    private var configLoader: MockConfigLoading!
    private var serverURL: URL!

    override func setUp() {
        super.setUp()

        getBundleService = .init()
        configLoader = MockConfigLoading()
        serverURL = URL(string: "https://test.tuist.dev")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL, fullHandle: "tuist/test"))

        subject = BundleShowService(
            getBundleService: getBundleService,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        getBundleService = nil
        subject = nil

        super.tearDown()
    }

    func test_bundle_show() async throws {
        try await withMockedDependencies {
            // Given
            let bundle = ServerBundle.test(
                id: "bundle-123",
                name: "TestApp",
                version: "1.0.0",
                gitBranch: "main",
                installSize: 1024000
            )

            given(getBundleService).getBundle(
                serverURL: .value(serverURL),
                fullHandle: .value("tuist/test"),
                bundleId: .value("bundle-123")
            ).willReturn(bundle)

            // When
            try await subject.run(
                bundleId: "bundle-123",
                directory: nil
            )

            // Then
            XCTAssertPrinterOutputContains("\"id\" : \"bundle-123\"")
            XCTAssertPrinterOutputContains("\"name\" : \"TestApp\"")
            XCTAssertPrinterOutputContains("\"version\" : \"1.0.0\"")
            XCTAssertPrinterOutputContains("\"installSize\" : 1024000")
        }
    }

    func test_bundle_show_with_custom_directory() async throws {
        try await withMockedDependencies {
            // Given
            let bundle = ServerBundle.test(id: "bundle-456")
            
            given(getBundleService).getBundle(
                serverURL: .any,
                fullHandle: .any,
                bundleId: .value("bundle-456")
            ).willReturn(bundle)

            // When
            try await subject.run(
                bundleId: "bundle-456",
                directory: "/custom/path"
            )

            // Then
            verify(configLoader).loadConfig(path: .value(try AbsolutePath(validating: "/custom/path")))
            verify(getBundleService).getBundle(
                serverURL: .value(serverURL),
                fullHandle: .value("tuist/test"),
                bundleId: .value("bundle-456")
            )
        }
    }

    func test_bundle_show_with_artifacts() async throws {
        try await withMockedDependencies {
            // Given
            let artifacts = [
                ServerBundleArtifact(
                    id: "artifact-1",
                    artifactType: "file",
                    path: "app.ipa",
                    size: 1024,
                    shasum: "abc123",
                    children: nil
                )
            ]
            let bundle = ServerBundle.test(
                id: "bundle-789",
                artifacts: artifacts
            )

            given(getBundleService).getBundle(
                serverURL: .any,
                fullHandle: .any,
                bundleId: .any
            ).willReturn(bundle)

            // When
            try await subject.run(
                bundleId: "bundle-789",
                directory: nil
            )

            // Then
            XCTAssertPrinterOutputContains("\"artifacts\"")
            XCTAssertPrinterOutputContains("\"path\" : \"app.ipa\"")
            XCTAssertPrinterOutputContains("\"size\" : 1024")
        }
    }
}