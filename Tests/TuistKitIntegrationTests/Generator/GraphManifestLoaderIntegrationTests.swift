import Basic
import Foundation
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class GraphManifestLoaderTests: TuistTestCase {
    var subject: GraphManifestLoader!

    override func setUp() {
        super.setUp()
        subject = GraphManifestLoader()
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_loadTuistConfig() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let content = """
        import ProjectDescription
        let config = TuistConfig(generationOptions: [])
        """

        let manifestPath = temporaryPath.appending(component: Manifest.tuistConfig.fileName)
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        // When
        _ = try subject.loadTuistConfig(at: temporaryPath)
    }

    func test_loadProject() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let content = """
        import ProjectDescription
        let project = Project(name: "tuist")
        """

        let manifestPath = temporaryPath.appending(component: Manifest.project.fileName)
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        // When
        let got = try subject.loadProject(at: temporaryPath)

        // Then
        XCTAssertEqual(got.name, "tuist")
    }

    func test_loadWorkspace() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let content = """
        import ProjectDescription
        let workspace = Workspace(name: "tuist", projects: [])
        """

        let manifestPath = temporaryPath.appending(component: Manifest.workspace.fileName)
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        // When
        let got = try subject.loadWorkspace(at: temporaryPath)

        // Then
        XCTAssertEqual(got.name, "tuist")
    }

    func test_loadSetup() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let content = """
        import ProjectDescription
        let setup = Setup([
                        .custom(name: "hello", meet: ["a", "b"], isMet: ["c"])
                    ])
        """

        let manifestPath = temporaryPath.appending(component: Manifest.setup.fileName)
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        // When
        let got = try subject.loadSetup(at: temporaryPath)

        // Then
        let customUp = got.first as? UpCustom
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(customUp?.name, "hello")
        XCTAssertEqual(customUp?.meet, ["a", "b"])
        XCTAssertEqual(customUp?.isMet, ["c"])
    }

    func test_load_invalidFormat() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let content = """
        import ABC
        let project
        """

        let manifestPath = temporaryPath.appending(component: Manifest.project.fileName)
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        // When / Then
        XCTAssertThrowsError(
            try subject.loadProject(at: temporaryPath)
        )
    }

    func test_load_missingManifest() throws {
        let temporaryPath = try self.temporaryPath()
        XCTAssertThrowsError(
            try subject.loadProject(at: temporaryPath)
        ) { error in
            XCTAssertEqual(error as? GraphManifestLoaderError, GraphManifestLoaderError.manifestNotFound(.project, temporaryPath))
        }
    }

    func test_manifestPath() throws {
        // Given
        let fileHandler = FileHandler()
        let temporaryPath = try self.temporaryPath()
        let manifestsPaths = Manifest.allCases.map {
            temporaryPath.appending(component: $0.fileName)
        }
        try manifestsPaths.forEach { try fileHandler.touch($0) }

        // When
        let got = try Manifest.allCases.map {
            try subject.manifestPath(at: temporaryPath, manifest: $0)
        }

        // Then
        XCTAssertEqual(got, manifestsPaths)
    }

    func test_manifestsAt() throws {
        // Given
        let fileHandler = FileHandler()
        let temporaryPath = try self.temporaryPath()
        try fileHandler.touch(temporaryPath.appending(component: "Project.swift"))
        try fileHandler.touch(temporaryPath.appending(component: "Workspace.swift"))
        try fileHandler.touch(temporaryPath.appending(component: "Setup.swift"))
        try fileHandler.touch(temporaryPath.appending(component: "TuistConfig.swift"))

        // When
        let got = subject.manifests(at: temporaryPath)

        // Then
        XCTAssertTrue(got.contains(.project))
        XCTAssertTrue(got.contains(.workspace))
        XCTAssertTrue(got.contains(.setup))
        XCTAssertTrue(got.contains(.tuistConfig))
    }
}
