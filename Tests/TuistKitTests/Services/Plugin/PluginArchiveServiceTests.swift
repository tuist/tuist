import MockableTest
import Path
import TuistLoader
import TuistSupport
import TuistSupportTesting
import XCTest
@testable import TuistKit

final class PluginArchiveServiceTests: TuistUnitTestCase {
    private var subject: PluginArchiveService!
    private var swiftPackageManagerController: MockSwiftPackageManagerController!
    private var packageInfoLoader: MockPackageInfoLoading!
    private var manifestLoader: MockManifestLoading!
    private var fileArchiverFactory: MockFileArchivingFactorying!

    override func setUp() {
        super.setUp()
        swiftPackageManagerController = MockSwiftPackageManagerController()
        packageInfoLoader = .init()
        manifestLoader = .init()
        fileArchiverFactory = MockFileArchivingFactorying()
        subject = PluginArchiveService(
            swiftPackageManagerController: swiftPackageManagerController,
            packageInfoLoader: packageInfoLoader,
            manifestLoader: manifestLoader,
            fileArchiverFactory: fileArchiverFactory
        )
    }

    override func tearDown() {
        subject = nil
        swiftPackageManagerController = nil
        packageInfoLoader = nil
        manifestLoader = nil
        fileArchiverFactory = nil
        super.tearDown()
    }

    func test_run_when_no_task_products_defined() async throws {
        // Given
        given(packageInfoLoader)
            .loadPackageInfo(at: .any)
            .willReturn(
                PackageInfo.test(
                    products: [
                        PackageInfo.Product(
                            name: "my-non-task-executable",
                            type: .executable,
                            targets: []
                        ),
                    ]
                )
            )

        // When
        try await subject.run(path: nil)

        // Then
        XCTAssertPrinterContains(
            "No tasks found - make sure you have executable products with `tuist-` prefix defined in your manifest.",
            at: .warning,
            ==
        )
    }

    func test_run() async throws {
        // Given
        let path = try temporaryPath()
        given(packageInfoLoader)
            .loadPackageInfo(at: .any)
            .willReturn(
                PackageInfo.test(
                    products: [
                        PackageInfo.Product(
                            name: "my-non-task-executable",
                            type: .executable,
                            targets: []
                        ),
                        PackageInfo.Product(
                            name: "tuist-one",
                            type: .executable,
                            targets: []
                        ),
                        PackageInfo.Product(
                            name: "tuist-two",
                            type: .executable,
                            targets: []
                        ),
                        PackageInfo.Product(
                            name: "tuist-three",
                            type: .library(.automatic),
                            targets: []
                        ),
                    ]
                )
            )
        given(manifestLoader)
            .loadPlugin(at: .any)
            .willReturn(.test(name: "TestPlugin"))

        var builtProducts: [String] = []
        swiftPackageManagerController.loadBuildFatReleaseBinaryStub = { _, product, _, _ in
            builtProducts.append(product)
        }
        let fileArchiver = MockFileArchiving()
        given(fileArchiverFactory).makeFileArchiver(for: .any).willReturn(fileArchiver)
        let zipPath = path.appending(components: "test-zip")
        given(fileArchiver).zip(name: .any).willReturn(zipPath)
        given(fileArchiver)
            .delete()
            .willReturn()
        try fileHandler.createFolder(zipPath)

        // When
        try await subject.run(path: path.pathString)

        // Then
        verify(packageInfoLoader)
            .loadPackageInfo(at: .value(path))
            .called(1)
        XCTAssertEqual(builtProducts, ["tuist-one", "tuist-two"])

        _ = verify(fileArchiver).zip(name: .value("TestPlugin.tuist-plugin.zip"))

        XCTAssertTrue(
            fileHandler.isFolder(
                path.appending(component: "TestPlugin.tuist-plugin.zip")
            )
        )
    }
}
