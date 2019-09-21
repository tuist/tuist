import Basic
import Foundation
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistKit

final class GraphManifestLoaderErrorTests: XCTestCase {
    func test_description() {
        XCTAssertEqual(GraphManifestLoaderError.projectDescriptionNotFound(AbsolutePath("/test")).description, "Couldn't find ProjectDescription.framework at path /test")
        XCTAssertEqual(GraphManifestLoaderError.unexpectedOutput(AbsolutePath("/test/")).description, "Unexpected output trying to parse the manifest at path /test")
        XCTAssertEqual(GraphManifestLoaderError.manifestNotFound(.project, AbsolutePath("/test/")).description, "Project.swift not found at path /test")
        XCTAssertEqual(GraphManifestLoaderError.manifestNotFound(nil, AbsolutePath("/test/")).description, "Manifest not found at path /test")
    }

    func test_type() {
        XCTAssertEqual(GraphManifestLoaderError.projectDescriptionNotFound(AbsolutePath("/test")).type, .bug)
        XCTAssertEqual(GraphManifestLoaderError.unexpectedOutput(AbsolutePath("/test/")).type, .bug)
        XCTAssertEqual(GraphManifestLoaderError.manifestNotFound(.project, AbsolutePath("/test/")).type, .abort)
    }
}

final class ManifestTests: XCTestCase {
    func test_fileName() {
        XCTAssertEqual(Manifest.project.fileName, "Project.swift")
        XCTAssertEqual(Manifest.workspace.fileName, "Workspace.swift")
        XCTAssertEqual(Manifest.setup.fileName, "Setup.swift")
    }
}

final class GraphManifestLoaderTests: XCTestCase {
    var fileHandler: MockFileHandler!
    var subject: GraphManifestLoader!

    override func setUp() {
        super.setUp()
        mockAllSystemInteractions()
        fileHandler = sharedMockFileHandler()

        subject = GraphManifestLoader()
    }

    func test_loadTuistConfig() throws {
        // Given
        let content = """
        import ProjectDescription
        let config = TuistConfig(generationOptions: [.generateManifest])
        """

        let manifestPath = fileHandler.currentPath.appending(component: Manifest.tuistConfig.fileName)
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        // When
        let got = try subject.loadTuistConfig(at: fileHandler.currentPath)

        // Then
        XCTAssertTrue(got.generationOptions.contains(.generateManifest))
    }

    func test_loadProject() throws {
        // Given
        let content = """
        import ProjectDescription
        let project = Project(name: "tuist")
        """

        let manifestPath = fileHandler.currentPath.appending(component: Manifest.project.fileName)
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        // When
        let got = try subject.loadProject(at: fileHandler.currentPath)

        // Then

        XCTAssertEqual(got.name, "tuist")
    }

    func test_loadWorkspace() throws {
        // Given
        let content = """
        import ProjectDescription
        let workspace = Workspace(name: "tuist", projects: [])
        """

        let manifestPath = fileHandler.currentPath.appending(component: Manifest.workspace.fileName)
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        // When
        let got = try subject.loadWorkspace(at: fileHandler.currentPath)

        // Then
        XCTAssertEqual(got.name, "tuist")
    }

    func test_loadSetup() throws {
        // Given
        let content = """
        import ProjectDescription
        let setup = Setup([
                        .custom(name: "hello", meet: ["a", "b"], isMet: ["c"])
                    ])
        """

        let manifestPath = fileHandler.currentPath.appending(component: Manifest.setup.fileName)
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        // When
        let got = try subject.loadSetup(at: fileHandler.currentPath)

        // Then
        let customUp = got.first as? UpCustom
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(customUp?.name, "hello")
        XCTAssertEqual(customUp?.meet, ["a", "b"])
        XCTAssertEqual(customUp?.isMet, ["c"])
    }

    func test_load_invalidFormat() throws {
        // Given
        let content = """
        import ABC
        let project
        """

        let manifestPath = fileHandler.currentPath.appending(component: Manifest.project.fileName)
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        // When / Then
        XCTAssertThrowsError(
            try subject.loadProject(at: fileHandler.currentPath)
        )
    }

    func test_load_missingManifest() throws {
        XCTAssertThrowsError(
            try subject.loadProject(at: fileHandler.currentPath)
        ) { error in
            XCTAssertEqual(error as? GraphManifestLoaderError, GraphManifestLoaderError.manifestNotFound(.project, fileHandler.currentPath))
        }
    }

    func test_manifestPath() throws {
        // Given
        let manifestsPaths = Manifest.allCases.map {
            fileHandler.currentPath.appending(component: $0.fileName)
        }
        try manifestsPaths.forEach { try fileHandler.touch($0) }

        // When
        let got = try Manifest.allCases.map {
            try subject.manifestPath(at: fileHandler.currentPath, manifest: $0)
        }

        // Then
        XCTAssertEqual(got, manifestsPaths)
    }

    func test_manifestsAt() throws {
        // Given
        try fileHandler.touch(fileHandler.currentPath.appending(component: "Project.swift"))
        try fileHandler.touch(fileHandler.currentPath.appending(component: "Workspace.swift"))
        try fileHandler.touch(fileHandler.currentPath.appending(component: "Setup.swift"))
        try fileHandler.touch(fileHandler.currentPath.appending(component: "TuistConfig.swift"))

        // When
        let got = subject.manifests(at: fileHandler.currentPath)

        // Then
        XCTAssertTrue(got.contains(.project))
        XCTAssertTrue(got.contains(.workspace))
        XCTAssertTrue(got.contains(.setup))
        XCTAssertTrue(got.contains(.tuistConfig))
    }
}
