import Basic
import Foundation
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class ManifestLoaderTests: TuistTestCase {
    var subject: ManifestLoader!

    override func setUp() {
        super.setUp()
        subject = ManifestLoader()
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_loadConfig() throws {
        // Given
        let versions = Versions.test()
        let temporaryPath = try self.temporaryPath()
        let content = """
        import ProjectDescription
        let config = Config(generationOptions: [])
        """

        let manifestPath = temporaryPath.appending(component: Manifest.config.fileName)
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        // When
        _ = try subject.loadConfig(at: temporaryPath, versions: versions)
    }

    func test_loadProject() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let versions = Versions.test()
        let content = """
        import ProjectDescription
        let project = Project(name: "tuist")
        """

        let manifestPath = temporaryPath.appending(component: Manifest.project.fileName)
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        // When
        let got = try subject.loadProject(at: temporaryPath, versions: versions)

        // Then
        XCTAssertEqual(got.name, "tuist")
    }

    func test_loadWorkspace() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let versions = Versions.test()
        let content = """
        import ProjectDescription
        let workspace = Workspace(name: "tuist", projects: [])
        """

        let manifestPath = temporaryPath.appending(component: Manifest.workspace.fileName)
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        // When
        let got = try subject.loadWorkspace(at: temporaryPath, versions: versions)

        // Then
        XCTAssertEqual(got.name, "tuist")
    }

    func test_loadSetup() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let versions = Versions.test()
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
        let got = try subject.loadSetup(at: temporaryPath, versions: versions)

        // Then
        let customUp = got.first as? UpCustom
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(customUp?.name, "hello")
        XCTAssertEqual(customUp?.meet, ["a", "b"])
        XCTAssertEqual(customUp?.isMet, ["c"])
    }

    func test_loadTemplate() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let versions = Versions.test()
        let content = """
        import ProjectDescription
        
        let template = Template(
            description: "Template description"
        )
        """

        let manifestPath = temporaryPath.appending(component: "Template.swift")
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        // When
        let got = try subject.loadTemplate(at: temporaryPath, versions: versions)

        // Then
        XCTAssertEqual(got.description, "Template description")
    }

    func test_load_invalidFormat() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let versions = Versions.test()
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
            try subject.loadProject(at: temporaryPath, versions: versions)
        )
    }

    func test_load_missingManifest() throws {
        let temporaryPath = try self.temporaryPath()
        let versions = Versions.test()
        XCTAssertThrowsError(
            try subject.loadProject(at: temporaryPath, versions: versions)
        ) { error in
            XCTAssertEqual(error as? ManifestLoaderError, ManifestLoaderError.manifestNotFound(.project, temporaryPath))
        }
    }

    func test_manifestsAt() throws {
        // Given
        let fileHandler = FileHandler()
        let temporaryPath = try self.temporaryPath()
        try fileHandler.touch(temporaryPath.appending(component: "Project.swift"))
        try fileHandler.touch(temporaryPath.appending(component: "Workspace.swift"))
        try fileHandler.touch(temporaryPath.appending(component: "Setup.swift"))
        try fileHandler.touch(temporaryPath.appending(component: "Config.swift"))

        // When
        let got = subject.manifests(at: temporaryPath)

        // Then
        XCTAssertTrue(got.contains(.project))
        XCTAssertTrue(got.contains(.workspace))
        XCTAssertTrue(got.contains(.setup))
        XCTAssertTrue(got.contains(.config))
    }
}
