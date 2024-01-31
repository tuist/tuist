import Foundation
import TSCBasic
import XCTest

@testable import TuistLoader
@testable import TuistSupport
@testable import TuistSupportTesting

final class ManifestLoaderTests: TuistTestCase {
    var subject: ManifestLoader!

    override func setUp() {
        super.setUp()
        subject = ManifestLoader()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_loadConfig() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let content = """
        import ProjectDescription
        let config = Config()
        """

        let manifestPath = temporaryPath.appending(component: Manifest.config.fileName(temporaryPath))
        try content.write(
            to: manifestPath.url,
            atomically: true,
            encoding: .utf8
        )

        // When
        _ = try subject.loadConfig(at: temporaryPath)
    }

    func test_loadPlugin() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let content = """
        import ProjectDescription
        let plugin = Plugin(name: "TestPlugin")
        """

        let manifestPath = temporaryPath.appending(component: Manifest.plugin.fileName(temporaryPath))
        try content.write(to: manifestPath.url, atomically: true, encoding: .utf8)

        // When
        _ = try subject.loadPlugin(at: temporaryPath)
    }

    func test_loadProject() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let content = """
        import ProjectDescription
        let project = Project(name: "tuist")
        """

        let manifestPath = temporaryPath.appending(component: Manifest.project.fileName(temporaryPath))
        try content.write(
            to: manifestPath.url,
            atomically: true,
            encoding: .utf8
        )

        // When
        let got = try subject.loadProject(at: temporaryPath)

        // Then
        XCTAssertEqual(got.name, "tuist")
    }

    func test_loadPackage() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let content = """
        // swift-tools-version: 5.9
        import PackageDescription

        #if TUIST
        import ProjectDescription

        let packageSettings = PackageSettings(
            platforms: [.iOS, .watchOS]
        )

        #endif

        let package = Package(
            name: "PackageName",
            products: [
                .executable(name: "tuist", targets: ["tuist"]),
            ],
            dependencies: [],
            targets: [
                .target(
                    name: "tuist",
                    dependencies: []
                ),
            ]
        )

        """

        let manifestPath = temporaryPath.appending(
            components: [
                Constants.tuistDirectoryName,
                Manifest.package.fileName(temporaryPath),
            ]
        )
        try FileHandler.shared.createFolder(temporaryPath.appending(component: Constants.tuistDirectoryName))
        try content.write(
            to: manifestPath.url,
            atomically: true,
            encoding: .utf8
        )

        // When
        let got = try subject.loadPackage(at: manifestPath.parentDirectory)

        // Then
        XCTAssertEqual(
            got,
            .test(
                products: [
                    PackageInfo.Product(name: "tuist", type: .executable, targets: ["tuist"]),
                ],
                targets: [
                    PackageInfo.Target(
                        name: "tuist",
                        path: nil,
                        url: nil,
                        sources: nil,
                        resources: [],
                        exclude: [],
                        dependencies: [],
                        publicHeadersPath: nil,
                        type: .regular,
                        settings: [],
                        checksum: nil,
                        packageAccess: true
                    ),
                ]
            )
        )
    }

    func test_loadPackageSettings() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let content = """
        // swift-tools-version: 5.9
        import PackageDescription

        #if TUIST
        import ProjectDescription

        let packageSettings = PackageSettings(
            platforms: [.iOS, .watchOS]
        )

        #endif

        let package = Package(
            name: "PackageName",
            dependencies: [
                .package(url: "https://github.com/Alamofire/Alamofire", exact: "5.8.0"),
            ]
        )

        """

        let manifestPath = temporaryPath.appending(
            components: [
                Constants.tuistDirectoryName,
                Manifest.package.fileName(temporaryPath),
            ]
        )
        try FileHandler.shared.createFolder(temporaryPath.appending(component: Constants.tuistDirectoryName))
        try content.write(
            to: manifestPath.url,
            atomically: true,
            encoding: .utf8
        )

        // When
        let got = try subject.loadPackageSettings(at: temporaryPath)

        // Then
        XCTAssertEqual(
            got,
            .init(platforms: [.iOS, .watchOS])
        )
    }

    func test_loadPackageSettings_without_package_settings() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let content = """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "PackageName",
            dependencies: []
        )

        """

        let manifestPath = temporaryPath.appending(
            components: [
                Constants.tuistDirectoryName,
                Manifest.package.fileName(temporaryPath),
            ]
        )
        try FileHandler.shared.createFolder(temporaryPath.appending(component: Constants.tuistDirectoryName))
        try content.write(
            to: manifestPath.url,
            atomically: true,
            encoding: .utf8
        )

        // When
        let got = try subject.loadPackageSettings(at: temporaryPath)

        // Then
        XCTAssertEqual(
            got,
            .init()
        )
    }

    func test_loadWorkspace() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let content = """
        import ProjectDescription
        let workspace = Workspace(name: "tuist", projects: [])
        """

        let manifestPath = temporaryPath.appending(component: Manifest.workspace.fileName(temporaryPath))
        try content.write(
            to: manifestPath.url,
            atomically: true,
            encoding: .utf8
        )

        // When
        let got = try subject.loadWorkspace(at: temporaryPath)

        // Then
        XCTAssertEqual(got.name, "tuist")
    }

    func test_loadTemplate() throws {
        // Given
        let temporaryPath = try temporaryPath().appending(component: "folder")
        try fileHandler.createFolder(temporaryPath)
        let content = """
        import ProjectDescription

        let template = Template(
            description: "Template description",
            items: []
        )
        """

        let manifestPath = temporaryPath.appending(component: "folder.swift")
        try content.write(
            to: manifestPath.url,
            atomically: true,
            encoding: .utf8
        )

        // When
        let got = try subject.loadTemplate(at: temporaryPath)

        // Then
        XCTAssertEqual(got.description, "Template description")
    }

    func test_load_invalidFormat() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let content = """
        import ABC
        let project
        """

        let manifestPath = temporaryPath.appending(component: Manifest.project.fileName(temporaryPath))
        try content.write(
            to: manifestPath.url,
            atomically: true,
            encoding: .utf8
        )

        // When / Then
        XCTAssertThrowsError(
            try subject.loadProject(at: temporaryPath)
        )
    }

    func test_load_missingManifest() throws {
        let temporaryPath = try temporaryPath()
        XCTAssertThrowsError(
            try subject.loadProject(at: temporaryPath)
        ) { error in
            XCTAssertEqual(error as? ManifestLoaderError, ManifestLoaderError.manifestNotFound(.project, temporaryPath))
        }
    }

    func test_manifestsAt() throws {
        // Given
        let fileHandler = FileHandler()
        let temporaryPath = try temporaryPath()
        try fileHandler.touch(temporaryPath.appending(component: "Project.swift"))
        try fileHandler.touch(temporaryPath.appending(component: "Workspace.swift"))
        try fileHandler.touch(temporaryPath.appending(component: "Config.swift"))

        // When
        let got = subject.manifests(at: temporaryPath)

        // Then
        XCTAssertTrue(got.contains(.project))
        XCTAssertTrue(got.contains(.workspace))
        XCTAssertTrue(got.contains(.config))
    }

    func test_manifestLoadError() throws {
        // Given
        let fileHandler = FileHandler()
        let temporaryPath = try temporaryPath()
        let configPath = temporaryPath.appending(component: "Config.swift")
        try fileHandler.touch(configPath)
        let data = try fileHandler.readFile(configPath)

        // When
        XCTAssertThrowsError(
            try subject.loadConfig(at: temporaryPath)
        ) { error in
            XCTAssertEqual(
                error as? ManifestLoaderError,
                .manifestLoadingFailed(
                    path: temporaryPath.appending(component: "Config.swift"),
                    data: data,
                    context: """
                    The encoded data for the manifest is corrupted.
                    The given data was not valid JSON.
                    """
                )
            )
        }
    }
}
