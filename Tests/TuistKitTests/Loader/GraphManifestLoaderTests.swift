import Basic
import Foundation
@testable import TuistCoreTesting
@testable import TuistKit
import XCTest

final class GraphManifestLoaderErrorTests: XCTestCase {
    func test_description() {
        XCTAssertEqual(GraphManifestLoaderError.projectDescriptionNotFound(AbsolutePath("/test")).description, "Couldn't find ProjectDescription.framework at path /test")
        XCTAssertEqual(GraphManifestLoaderError.unexpectedOutput(AbsolutePath("/test/")).description, "Unexpected output trying to parse the manifest at path /test")
        XCTAssertEqual(GraphManifestLoaderError.invalidYaml(AbsolutePath("/test/")).description, "Invalid yaml at path /test. The root element should be a dictionary")
        XCTAssertEqual(GraphManifestLoaderError.manifestNotFound(.project, AbsolutePath("/test/")).description, "Project not found at /test")
    }

    func test_type() {
        XCTAssertEqual(GraphManifestLoaderError.projectDescriptionNotFound(AbsolutePath("/test")).type, .bug)
        XCTAssertEqual(GraphManifestLoaderError.unexpectedOutput(AbsolutePath("/test/")).type, .bug)
        XCTAssertEqual(GraphManifestLoaderError.invalidYaml(AbsolutePath("/test/")).type, .abort)
        XCTAssertEqual(GraphManifestLoaderError.manifestNotFound(.project, AbsolutePath("/test/")).type, .abort)
    }
}

final class ManifestTests: XCTestCase {
    func test_fileName() {
        XCTAssertEqual(Manifest.project.fileName, "Project")
        XCTAssertEqual(Manifest.workspace.fileName, "Workspace")
    }

    func test_supportedExtensions() {
        let expected = Set(arrayLiteral: "json", "swift", "yaml", "yml")
        XCTAssertEqual(Manifest.supportedExtensions, expected)
    }
}

final class GraphManifestLoaderTests: XCTestCase {
    var fileHandler: MockFileHandler!
    var subject: GraphManifestLoader!

    override func setUp() {
        super.setUp()
        fileHandler = try! MockFileHandler()
        subject = GraphManifestLoader(fileHandler: fileHandler)
    }

    func test_load_when_swift() throws {
        let content = """
        import ProjectDescription
        let project = Project(name: "tuist")
        """

        let manifestPath = fileHandler.currentPath.appending(component: "\(Manifest.project.fileName).swift")
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        let got = try subject.load(.project, path: fileHandler.currentPath)
        XCTAssertEqual(try got.get("name") as String, "tuist")
    }

    func test_load_when_json() throws {
        let content = """
        {
            "name": "tuist"
        }
        """

        let manifestPath = fileHandler.currentPath.appending(component: "\(Manifest.project.fileName).json")
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        let got = try subject.load(.project, path: fileHandler.currentPath)

        XCTAssertEqual(try got.get("name") as String, "tuist")
    }

    func test_load_when_yaml() throws {
        let content = """
        name: tuist
        """

        let manifestPath = fileHandler.currentPath.appending(component: "\(Manifest.project.fileName).yaml")
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        let got = try subject.load(.project, path: fileHandler.currentPath)

        XCTAssertEqual(try got.get("name") as String, "tuist")
    }

    func test_load_when_yml() throws {
        let content = """
        name: tuist
        """

        let manifestPath = fileHandler.currentPath.appending(component: "\(Manifest.project.fileName).yml")
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        let got = try subject.load(.project, path: fileHandler.currentPath)

        XCTAssertEqual(try got.get("name") as String, "tuist")
    }

    func test_manifestPath_when_swift() throws {
        try fileHandler.touch(fileHandler.currentPath.appending(component: "\(Manifest.project.fileName).swift"))
        let got = try subject.manifestPath(at: fileHandler.currentPath, manifest: .project)

        XCTAssertEqual(got, fileHandler.currentPath.appending(component: "\(Manifest.project.fileName).swift"))
    }

    func test_manifestPath_when_json() throws {
        try fileHandler.touch(fileHandler.currentPath.appending(component: "\(Manifest.project.fileName).json"))
        let got = try subject.manifestPath(at: fileHandler.currentPath, manifest: .project)

        XCTAssertEqual(got, fileHandler.currentPath.appending(component: "\(Manifest.project.fileName).json"))
    }

    func test_manifestPath_when_yaml() throws {
        try fileHandler.touch(fileHandler.currentPath.appending(component: "\(Manifest.project.fileName).yaml"))
        let got = try subject.manifestPath(at: fileHandler.currentPath, manifest: .project)

        XCTAssertEqual(got, fileHandler.currentPath.appending(component: "\(Manifest.project.fileName).yaml"))
    }

    func test_manifestPath_when_yml() throws {
        try fileHandler.touch(fileHandler.currentPath.appending(component: "\(Manifest.project.fileName).yml"))
        let got = try subject.manifestPath(at: fileHandler.currentPath, manifest: .project)

        XCTAssertEqual(got, fileHandler.currentPath.appending(component: "\(Manifest.project.fileName).yml"))
    }

    func test_manifestsAt_when_json() throws {
        try fileHandler.touch(fileHandler.currentPath.appending(component: "Project.json"))
        try fileHandler.touch(fileHandler.currentPath.appending(component: "Workspace.json"))
        let got = subject.manifests(at: fileHandler.currentPath)

        XCTAssertTrue(got.contains(.project))
        XCTAssertTrue(got.contains(.workspace))
    }

    func test_manifestsAt_when_swift() throws {
        try fileHandler.touch(fileHandler.currentPath.appending(component: "Project.swift"))
        try fileHandler.touch(fileHandler.currentPath.appending(component: "Workspace.swift"))
        let got = subject.manifests(at: fileHandler.currentPath)

        XCTAssertTrue(got.contains(.project))
        XCTAssertTrue(got.contains(.workspace))
    }

    func test_manifestsAt_when_yaml() throws {
        try fileHandler.touch(fileHandler.currentPath.appending(component: "Project.yaml"))
        try fileHandler.touch(fileHandler.currentPath.appending(component: "Workspace.yaml"))
        let got = subject.manifests(at: fileHandler.currentPath)

        XCTAssertTrue(got.contains(.project))
        XCTAssertTrue(got.contains(.workspace))
    }

    func test_manifestsAt_when_yml() throws {
        try fileHandler.touch(fileHandler.currentPath.appending(component: "Project.yml"))
        try fileHandler.touch(fileHandler.currentPath.appending(component: "Workspace.yml"))
        let got = subject.manifests(at: fileHandler.currentPath)

        XCTAssertTrue(got.contains(.project))
        XCTAssertTrue(got.contains(.workspace))
    }
}
