import Foundation
import Mockable
import TuistLoader
import TuistServer
import TuistTesting
import XCTest

@testable import TuistKit

final class BundleListServiceTests: TuistUnitTestCase {
    private var listBundlesService: MockListBundlesServicing!
    private var subject: BundleListService!
    private var configLoader: MockConfigLoading!
    private var serverURL: URL!

    override func setUp() {
        super.setUp()

        listBundlesService = .init()
        configLoader = MockConfigLoading()
        serverURL = URL(string: "https://test.tuist.dev")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL, fullHandle: "tuist/test"))

        subject = BundleListService(
            listBundlesService: listBundlesService,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        listBundlesService = nil
        subject = nil

        super.tearDown()
    }

    func test_bundle_list() async throws {
        try await withMockedDependencies {
            // Given
            let bundle1 = ServerBundle.test(
                id: "bundle-1",
                name: "TestApp1",
                version: "1.0.0",
                gitBranch: "main",
                installSize: 1024000
            )
            let bundle2 = ServerBundle.test(
                id: "bundle-2",
                name: "TestApp2",
                version: "1.1.0",
                gitBranch: "feature",
                installSize: 2048000
            )
            let response = ServerBundleListResponse.test(
                bundles: [bundle1, bundle2],
                meta: ServerBundleListMeta.test(totalCount: 2, hasNextPage: false)
            )

            given(listBundlesService).listBundles(
                serverURL: .any,
                fullHandle: .any,
                gitBranch: .any,
                page: .any,
                pageSize: .any
            ).willReturn(response)

            // When
            try await subject.run(
                json: false,
                directory: nil,
                gitBranch: nil,
                page: nil,
                pageSize: nil
            )

            // Then
            XCTAssertPrinterOutputContains("Listing bundles:")
            XCTAssertPrinterOutputContains("TestApp1 (v1.0.0)")
            XCTAssertPrinterOutputContains("TestApp2 (v1.1.0)")
            XCTAssertPrinterOutputContains("main")
            XCTAssertPrinterOutputContains("feature")
            XCTAssertPrinterOutputContains("Total: 2")
        }
    }

    func test_bundle_list_with_git_branch_filter() async throws {
        try await withMockedDependencies {
            // Given
            let bundle = ServerBundle.test(
                name: "TestApp",
                gitBranch: "feature"
            )
            let response = ServerBundleListResponse.test(
                bundles: [bundle],
                meta: ServerBundleListMeta.test(totalCount: 1)
            )

            given(listBundlesService).listBundles(
                serverURL: .value(serverURL),
                fullHandle: .value("tuist/test"),
                gitBranch: .value("feature"),
                page: .value(nil),
                pageSize: .value(nil)
            ).willReturn(response)

            // When
            try await subject.run(
                json: false,
                directory: nil,
                gitBranch: "feature",
                page: nil,
                pageSize: nil
            )

            // Then
            verify(listBundlesService).listBundles(
                serverURL: .value(serverURL),
                fullHandle: .value("tuist/test"),
                gitBranch: .value("feature"),
                page: .value(nil),
                pageSize: .value(nil)
            )
        }
    }

    func test_bundle_list_with_pagination() async throws {
        try await withMockedDependencies {
            // Given
            let response = ServerBundleListResponse.test(
                bundles: [ServerBundle.test()],
                meta: ServerBundleListMeta.test(totalCount: 10, hasNextPage: true)
            )

            given(listBundlesService).listBundles(
                serverURL: .value(serverURL),
                fullHandle: .value("tuist/test"),
                gitBranch: .value(nil),
                page: .value(2),
                pageSize: .value(5)
            ).willReturn(response)

            // When
            try await subject.run(
                json: false,
                directory: nil,
                gitBranch: nil,
                page: 2,
                pageSize: 5
            )

            // Then
            XCTAssertPrinterOutputContains("Page 2 of bundles (has more)")
            XCTAssertPrinterOutputContains("Total: 10")
        }
    }

    func test_bundle_list_when_none() async throws {
        try await withMockedDependencies {
            // Given
            let response = ServerBundleListResponse.test(
                bundles: [],
                meta: ServerBundleListMeta.test(totalCount: 0)
            )

            given(listBundlesService).listBundles(
                serverURL: .any,
                fullHandle: .any,
                gitBranch: .any,
                page: .any,
                pageSize: .any
            ).willReturn(response)

            // When
            try await subject.run(
                json: false,
                directory: nil,
                gitBranch: nil,
                page: nil,
                pageSize: nil
            )

            // Then
            XCTAssertPrinterOutputContains("No bundles found for this project.")
        }
    }

    func test_bundle_list_when_none_with_branch_filter() async throws {
        try await withMockedDependencies {
            // Given
            let response = ServerBundleListResponse.test(
                bundles: [],
                meta: ServerBundleListMeta.test(totalCount: 0)
            )

            given(listBundlesService).listBundles(
                serverURL: .any,
                fullHandle: .any,
                gitBranch: .any,
                page: .any,
                pageSize: .any
            ).willReturn(response)

            // When
            try await subject.run(
                json: false,
                directory: nil,
                gitBranch: "feature",
                page: nil,
                pageSize: nil
            )

            // Then
            XCTAssertPrinterOutputContains("No bundles found for this project. (filtered by git branch: feature)")
        }
    }

    func test_bundle_list_json_output() async throws {
        try await withMockedDependencies {
            // Given
            let bundle = ServerBundle.test(name: "TestApp")
            let response = ServerBundleListResponse.test(bundles: [bundle])

            given(listBundlesService).listBundles(
                serverURL: .any,
                fullHandle: .any,
                gitBranch: .any,
                page: .any,
                pageSize: .any
            ).willReturn(response)

            // When
            try await subject.run(
                json: true,
                directory: nil,
                gitBranch: nil,
                page: nil,
                pageSize: nil
            )

            // Then
            XCTAssertPrinterOutputContains("\"name\" : \"TestApp\"")
        }
    }
}