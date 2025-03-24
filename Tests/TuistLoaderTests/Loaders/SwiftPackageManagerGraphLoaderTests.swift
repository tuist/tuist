import Mockable
import ServiceContextModule
import TuistCore
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistLoader

final class SwiftPackageManagerGraphLoaderTests: TuistUnitTestCase {
    private var swiftPackageManagerController: MockSwiftPackageManagerControlling!
    private var packageInfoMapper: MockPackageInfoMapping!
    private var manifestLoader: MockManifestLoading!
    private var subject: SwiftPackageManagerGraphLoader!

    override func setUp() {
        super.setUp()
        swiftPackageManagerController = MockSwiftPackageManagerControlling()
        packageInfoMapper = MockPackageInfoMapping()
        manifestLoader = MockManifestLoading()
        subject = SwiftPackageManagerGraphLoader(
            packageInfoMapper: packageInfoMapper,
            manifestLoader: manifestLoader,
            fileSystem: fileSystem
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
        try await ServiceContext.withTestingDependencies {
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
                .resolveExternalDependencies(
                    path: .any,
                    packageInfos: .any,
                    packageToFolder: .any,
                    packageToTargetsToArtifactPaths: .any,
                    packageModuleAliases: .any
                )
                .willReturn([:])

            // When
            let _ = try await subject.load(
                packagePath: temporaryPath.appending(component: "Package.swift"),
                packageSettings: packageSettings
            )

            // Then
            XCTAssertPrinterOutputNotContains("We detected outdated dependencies. Please run \"tuist install\" to update them.")
        }
    }

    func test_load_warnOutdatedDependencies() async throws {
        try await ServiceContext.withTestingDependencies {
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

            let savedPackageResolvedPath = temporaryPath.appending(components: [".build", "Derived", "Package.resolved"])
            let currentPackageResolvedPath = temporaryPath.appending(component: "Package.resolved")
            try fileHandler.touch(savedPackageResolvedPath)
            try fileHandler.write("outdated", path: savedPackageResolvedPath, atomically: true)
            try fileHandler.touch(currentPackageResolvedPath)

            given(packageInfoMapper)
                .resolveExternalDependencies(
                    path: .any,
                    packageInfos: .any,
                    packageToFolder: .any,
                    packageToTargetsToArtifactPaths: .any,
                    packageModuleAliases: .any
                )
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
}
