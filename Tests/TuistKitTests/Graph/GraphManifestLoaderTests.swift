import Basic
import Foundation
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit

final class GraphManifestLoaderErrorTests: XCTestCase {
    func test_description() {
        XCTAssertEqual(GraphManifestLoaderError.projectDescriptionNotFound(AbsolutePath("/test")).description, "Couldn't find ProjectDescription.framework at path /test")
        XCTAssertEqual(GraphManifestLoaderError.unexpectedOutput(AbsolutePath("/test/")).description, "Unexpected output trying to parse the manifest at path /test")
        XCTAssertEqual(GraphManifestLoaderError.manifestNotFound(.project, AbsolutePath("/test/")).description, "Project.swift not found at path /test")
        XCTAssertEqual(GraphManifestLoaderError.manifestNotFound(nil, AbsolutePath("/test/")).description, "Manifest not found at path /test")
        XCTAssertEqual(GraphManifestLoaderError.setupNotFound(AbsolutePath("/test/")).description, "Setup.swift not found at path /test")
    }

    func test_type() {
        XCTAssertEqual(GraphManifestLoaderError.projectDescriptionNotFound(AbsolutePath("/test")).type, .bug)
        XCTAssertEqual(GraphManifestLoaderError.unexpectedOutput(AbsolutePath("/test/")).type, .bug)
        XCTAssertEqual(GraphManifestLoaderError.manifestNotFound(.project, AbsolutePath("/test/")).type, .abort)
        XCTAssertEqual(GraphManifestLoaderError.setupNotFound(AbsolutePath("/test/")).type, .abort)
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
    var deprecator: MockDeprecator!
    var subject: GraphManifestLoader!

    override func setUp() {
        super.setUp()
        fileHandler = try! MockFileHandler()
        deprecator = MockDeprecator()
        subject = GraphManifestLoader(fileHandler: fileHandler,
                                      deprecator: deprecator)
    }

    func test_load_when_swift() throws {
        let content = """
        import ProjectDescription
        let project = Project(name: "tuist")
        """

        let manifestPath = fileHandler.currentPath.appending(component: Manifest.project.fileName)
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        let got = try subject.load(.project, path: fileHandler.currentPath)
        XCTAssertEqual(try got.get("name") as String, "tuist")
    }

    func test_manifestPath_when_swift() throws {
        try fileHandler.touch(fileHandler.currentPath.appending(component: Manifest.project.fileName))
        let got = try subject.manifestPath(at: fileHandler.currentPath, manifest: .project)

        XCTAssertEqual(got, fileHandler.currentPath.appending(component: Manifest.project.fileName))
    }

    func test_manifestsAt_when_swift() throws {
        try fileHandler.touch(fileHandler.currentPath.appending(component: "Project.swift"))
        try fileHandler.touch(fileHandler.currentPath.appending(component: "Workspace.swift"))
        let got = subject.manifests(at: fileHandler.currentPath)

        XCTAssertTrue(got.contains(.project))
        XCTAssertTrue(got.contains(.workspace))
    }
}
