import MockableTest
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class SwiftPackageManagerGraphLoaderTests: TuistUnitTestCase {
    var swiftPackageManagerController: MockSwiftPackageManagerController!
    var packageInfoMapper: MockPackageInfoMapping!
    var manifestLoader: MockManifestLoading!
    var subject: SwiftPackageManagerGraphLoader!

    override func setUp() {
        super.setUp()
        swiftPackageManagerController = MockSwiftPackageManagerController()
        packageInfoMapper = MockPackageInfoMapping()
        manifestLoader = MockManifestLoading()
        subject = SwiftPackageManagerGraphLoader(
            swiftPackageManagerController: swiftPackageManagerController,
            packageInfoMapper: packageInfoMapper,
            manifestLoader: manifestLoader,
            fileHandler: FileHandler.shared
        )
    }

    override func tearDown() {
        subject = nil
        manifestLoader = nil
        packageInfoMapper = nil
        swiftPackageManagerController = nil
        super.tearDown()
    }

    func test_load() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let packageSettings = PackageSettings.test()

        let workspacePath = temporaryPath.appending(components: [".build", "workspace-state.json"])
        try fileHandler.createFolder(workspacePath.parentDirectory)
        try fileHandler.write(
            """
            {
              "object" : {
                "artifacts" : [],
                "dependencies" : []
              }
            }
            """,
            path: workspacePath,
            atomically: true
        )

        try fileHandler.touch(temporaryPath.appending(components: [".build", "Derived", "Package.resolved"]))
        try fileHandler.touch(temporaryPath.appending(component: "Package.resolved"))

        given(packageInfoMapper)
            .resolveExternalDependencies(packageInfos: .any, packageToFolder: .any, packageToTargetsToArtifactPaths: .any)
            .willReturn([:])

        // When
        let _ = try await subject.load(
            packagePath: temporaryPath.appending(component: "Package.swift"),
            packageSettings: packageSettings
        )

        // Then
        XCTAssertPrinterOutputNotContains("We detected outdated dependencies. Please run \"tuist install\" to update them.")
    }

    func test_load_warnOutdatedDependencies() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let packageSettings = PackageSettings.test()

        let workspacePath = temporaryPath.appending(components: [".build", "workspace-state.json"])
        try fileHandler.createFolder(workspacePath.parentDirectory)
        try fileHandler.write(
            """
            {
              "object" : {
                "artifacts" : [],
                "dependencies" : []
              }
            }
            """,
            path: workspacePath,
            atomically: true
        )

        try fileHandler.touch(temporaryPath.appending(components: [".build", "Derived", "Package.resolved"]))

        given(packageInfoMapper)
            .resolveExternalDependencies(packageInfos: .any, packageToFolder: .any, packageToTargetsToArtifactPaths: .any)
            .willReturn([:])

        // When
        let _ = try await subject.load(
            packagePath: temporaryPath.appending(component: "Package.swift"),
            packageSettings: packageSettings
        )

        // Then
        XCTAssertPrinterOutputContains("We detected outdated dependencies. Please run \"tuist install\" to update them.")
    }
}
