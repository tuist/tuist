import Foundation
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator

final class TargetTests: XCTestCase {
    var fileHandler: MockFileHandler!
    override func setUp() {
        do {
            fileHandler = try MockFileHandler()
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func test_validSourceExtensions() {
        XCTAssertEqual(Target.validSourceExtensions, ["m", "swift", "mm", "cpp", "c"])
    }

    func test_productName_when_staticLibrary() {
        let target = Target.test(name: "Test", product: .staticLibrary)
        XCTAssertEqual(target.productNameWithExtension, "libTest.a")
    }

    func test_productName_when_dynamicLibrary() {
        let target = Target.test(name: "Test", product: .dynamicLibrary)
        XCTAssertEqual(target.productNameWithExtension, "libTest.dylib")
    }

    func test_productName_when_app() {
        let target = Target.test(name: "Test", product: .app)
        XCTAssertEqual(target.productNameWithExtension, "Test.app")
    }

    func test_sequence_testBundles() {
        let app = Target.test(product: .app)
        let tests = Target.test(product: .unitTests)
        let targets = [app, tests]

        XCTAssertEqual(targets.testBundles, [tests])
    }

    func test_sequence_apps() {
        let app = Target.test(product: .app)
        let tests = Target.test(product: .unitTests)
        let targets = [app, tests]

        XCTAssertEqual(targets.apps, [app])
    }

    func test_sources() throws {
        // Given
        try fileHandler.createFiles([
            "sources/a.swift",
            "sources/b.h",
            "sources/b.m",
            "sources/c.mm",
            "sources/d.c",
            "sources/e.cpp",
            "sources/k.kt",
        ])

        // When
        let sources = try Target.sources(projectPath: fileHandler.currentPath,
                                         sources: [
                                             (glob: "sources/**", compilerFlags: nil),
                                             (glob: "sources/**", compilerFlags: nil),
                                         ])

        // Then
        let relativeSources = sources.map { $0.path.relative(to: fileHandler.currentPath).pathString }
        
        XCTAssertEqual(Set(relativeSources), Set([
            "sources/a.swift",
            "sources/b.m",
            "sources/c.mm",
            "sources/d.c",
            "sources/e.cpp",
            ]))
    }

    func test_resources() throws {
        // Given
        let folders = try fileHandler.createFolders([
            "resources/d.xcassets",
            "resources/g.bundle",
        ])

        let files = try fileHandler.createFiles([
            "resources/a.png",
            "resources/b.jpg",
            "resources/b.jpeg",
            "resources/c.pdf",
            "resources/e.ttf",
            "resources/f.otf",
        ])

        let paths = folders + files

        // When
        let resources = paths.filter { Target.isResource(path: $0, fileHandler: fileHandler) }

        // Then
        let relativeResources = resources.map { $0.relative(to: fileHandler.currentPath).pathString }
        XCTAssertEqual(relativeResources, [
            "resources/d.xcassets",
            "resources/g.bundle",
            "resources/a.png",
            "resources/b.jpg",
            "resources/b.jpeg",
            "resources/c.pdf",
            "resources/e.ttf",
            "resources/f.otf",
        ])
    }
}
