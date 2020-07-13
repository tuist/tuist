import Foundation
import TSCBasic
import XCTest
@testable import TuistCore
@testable import TuistSupportTesting

final class TargetTests: TuistUnitTestCase {
    func test_validSourceExtensions() {
        XCTAssertEqual(Target.validSourceExtensions, ["m", "swift", "mm", "cpp", "c", "d", "intentdefinition", "xcmappingmodel", "metal"])
    }

    func test_productName_when_staticLibrary() {
        let target = Target.test(name: "Test", product: .staticLibrary)
        XCTAssertEqual(target.productNameWithExtension, "libTest.a")
    }

    func test_productName_when_dynamicLibrary() {
        let target = Target.test(name: "Test", product: .dynamicLibrary)
        XCTAssertEqual(target.productNameWithExtension, "libTest.dylib")
    }

    func test_productName_when_nil() {
        let target = Target.test(name: "Test-Module", productName: nil)
        XCTAssertEqual(target.productName, "Test_Module")
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
        let temporaryPath = try self.temporaryPath()
        try createFiles([
            "sources/a.swift",
            "sources/b.h",
            "sources/b.m",
            "sources/c.mm",
            "sources/d.c",
            "sources/e.cpp",
            "sources/k.kt",
            "sources/n.metal",
        ])

        // When
        let sources = try Target.sources(sources: [
            (glob: temporaryPath.appending(RelativePath("sources/**")).pathString, excluding: [], compilerFlags: nil),
            (glob: temporaryPath.appending(RelativePath("sources/**")).pathString, excluding: [], compilerFlags: nil),
        ])

        // Then
        let relativeSources = sources.map { $0.path.relative(to: temporaryPath).pathString }

        XCTAssertEqual(Set(relativeSources), Set([
            "sources/a.swift",
            "sources/b.m",
            "sources/c.mm",
            "sources/d.c",
            "sources/e.cpp",
            "sources/n.metal",
        ]))
    }

    func test_sources_excluding() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        try createFiles([
            "sources/a.swift",
            "sources/b.swift",
            "sources/aTests.swift",
            "sources/bTests.swift",
            "sources/kTests.kt",
            "sources/c/c.swift",
            "sources/c/cTests.swift",
        ])

        // When
        let sources = try Target.sources(sources: [
            (glob: temporaryPath.appending(RelativePath("sources/**")).pathString,
             excluding: [temporaryPath.appending(RelativePath("sources/**/*Tests.swift")).pathString],
             compilerFlags: nil),
        ])

        // Then
        let relativeSources = sources.map { $0.path.relative(to: temporaryPath).pathString }

        XCTAssertEqual(Set(relativeSources), Set([
            "sources/a.swift",
            "sources/b.swift",
            "sources/c/c.swift",
        ]))
    }

    func test_sources_excluding_multiple_paths() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        try createFiles([
            "sources/a.swift",
            "sources/b.swift",
            "sources/aTests.swift",
            "sources/c/cType+Fake.swift",
            "sources/aType+Fake.swift",
            "sources/bTests.swift",
            "sources/kTests.kt",
            "sources/c/c.swift",
            "sources/c/cTests.swift",
            "sources/d.h",
            "sources/d.m",
            "sources/d/d.m",
        ])
        let excluding: [String] = [
            temporaryPath.appending(RelativePath("sources/**/*Tests.swift")).pathString,
            temporaryPath.appending(RelativePath("sources/**/*Fake.swift")).pathString,
            temporaryPath.appending(RelativePath("sources/**/*.m")).pathString,
        ]

        // When
        let sources = try Target.sources(sources: [
            (glob: temporaryPath.appending(RelativePath("sources/**")).pathString,
             excluding: excluding,
             compilerFlags: nil),
        ])

        // Then
        let relativeSources = sources.map { $0.path.relative(to: temporaryPath).pathString }

        XCTAssertEqual(Set(relativeSources), Set([
            "sources/a.swift",
            "sources/b.swift",
            "sources/c/c.swift",
        ]))
    }

    func test_resources() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let folders = try createFolders([
            "resources/d.xcassets",
            "resources/d.scnassets",
            "resources/g.bundle",
        ])

        let files = try createFiles([
            "resources/a.png",
            "resources/b.jpg",
            "resources/b.jpeg",
            "resources/c.pdf",
            "resources/e.ttf",
            "resources/f.otf",
        ])

        let paths = folders + files

        // When
        let resources = paths.filter { Target.isResource(path: $0) }

        // Then
        let relativeResources = resources.map { $0.relative(to: temporaryPath).pathString }
        XCTAssertEqual(relativeResources, [
            "resources/d.xcassets",
            "resources/d.scnassets",
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
