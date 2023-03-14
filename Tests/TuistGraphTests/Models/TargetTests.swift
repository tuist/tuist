import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest
@testable import TuistGraph
@testable import TuistGraphTesting
@testable import TuistSupportTesting

final class TargetErrorTests: TuistUnitTestCase {
    func test_description() {
        // Given
        let invalidGlobs: [InvalidGlob] = [.init(pattern: "**/*", nonExistentPath: .root)]

        // When
        let got = TargetError.invalidSourcesGlob(targetName: "Target", invalidGlobs: invalidGlobs).description

        // Then
        XCTAssertEqual(
            got,
            "The target Target has the following invalid source files globs:\n" + invalidGlobs.invalidGlobsDescription
        )
    }
}

final class TargetTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = Target.test(name: "Test", product: .staticLibrary)

        // Then
        XCTAssertCodable(subject)
    }

    func test_validSourceExtensions() {
        XCTAssertEqual(
            Target.validSourceExtensions,
            [
                "m",
                "swift",
                "mm",
                "cpp",
                "cc",
                "c",
                "d",
                "s",
                "intentdefinition",
                "xcmappingmodel",
                "metal",
                "mlmodel",
                "docc",
                "playground",
                "rcproject",
            ]
        )
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

    func test_productName_when_appClip() {
        let target = Target.test(name: "Test", product: .appClip)
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

    func test_sequence_appClips() {
        let appClip = Target.test(product: .appClip)
        let tests = Target.test(product: .unitTests)
        let targets = [appClip, tests]

        XCTAssertEqual(targets.apps, [appClip])
    }

    func test_sources() throws {
        // Given
        let temporaryPath = try temporaryPath()
        try createFiles([
            "sources/a.swift",
            "sources/b.h",
            "sources/b.m",
            "sources/c.mm",
            "sources/d.c",
            "sources/e.cpp",
            "sources/f.s",
            "sources/g.S",
            "sources/k.kt",
            "sources/n.metal",
        ])

        // When
        let sources = try Target.sources(targetName: "Target", sources: [
            SourceFileGlob(
                glob: temporaryPath.appending(RelativePath("sources/**")).pathString,
                excluding: [],
                compilerFlags: nil
            ),
            SourceFileGlob(
                glob: temporaryPath.appending(RelativePath("sources/**")).pathString,
                excluding: [],
                compilerFlags: nil
            ),
        ])

        // Then
        let relativeSources = sources.map { $0.path.relative(to: temporaryPath).pathString }

        XCTAssertEqual(Set(relativeSources), Set([
            "sources/a.swift",
            "sources/b.m",
            "sources/c.mm",
            "sources/d.c",
            "sources/f.s",
            "sources/g.S",
            "sources/e.cpp",
            "sources/n.metal",
        ]))
    }

    func test_sources_excluding() throws {
        // Given
        let temporaryPath = try temporaryPath()
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
        let sources = try Target.sources(targetName: "Target", sources: [
            SourceFileGlob(
                glob: temporaryPath.appending(RelativePath("sources/**")).pathString,
                excluding: [temporaryPath.appending(RelativePath("sources/**/*Tests.swift")).pathString],
                compilerFlags: nil
            ),
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
        let temporaryPath = try temporaryPath()
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
        let sources = try Target.sources(targetName: "Target", sources: [
            SourceFileGlob(
                glob: temporaryPath.appending(RelativePath("sources/**")).pathString,
                excluding: excluding,
                compilerFlags: nil
            ),
        ])

        // Then
        let relativeSources = sources.map { $0.path.relative(to: temporaryPath).pathString }

        XCTAssertEqual(Set(relativeSources), Set([
            "sources/a.swift",
            "sources/b.swift",
            "sources/c/c.swift",
        ]))
    }

    func test_sources_when_globs_are_invalid() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let invalidGlobs: [InvalidGlob] = [
            .init(
                pattern: temporaryPath.appending(RelativePath("invalid/path/**")).pathString,
                nonExistentPath: temporaryPath.appending(RelativePath("invalid/path"))
            ),
        ]
        let error = TargetError.invalidSourcesGlob(
            targetName: "Target",
            invalidGlobs: invalidGlobs
        )
        // When
        XCTAssertThrowsSpecific(try Target.sources(targetName: "Target", sources: [
            SourceFileGlob(glob: temporaryPath.appending(RelativePath("invalid/path/**")).pathString),
        ]), error)
    }

    func test_supportsResources() {
        XCTAssertFalse(Target.test(product: .dynamicLibrary).supportsResources)
        XCTAssertFalse(Target.test(product: .staticLibrary).supportsResources)
        XCTAssertFalse(Target.test(product: .staticFramework).supportsResources)
        XCTAssertTrue(Target.test(product: .app).supportsResources)
        XCTAssertTrue(Target.test(product: .framework).supportsResources)
        XCTAssertTrue(Target.test(product: .unitTests).supportsResources)
        XCTAssertTrue(Target.test(product: .uiTests).supportsResources)
        XCTAssertTrue(Target.test(product: .bundle).supportsResources)
        XCTAssertTrue(Target.test(product: .appExtension).supportsResources)
        XCTAssertTrue(Target.test(product: .watch2App).supportsResources)
        XCTAssertTrue(Target.test(product: .watch2Extension).supportsResources)
        XCTAssertTrue(Target.test(product: .messagesExtension).supportsResources)
        XCTAssertTrue(Target.test(product: .stickerPackExtension).supportsResources)
        XCTAssertTrue(Target.test(product: .appClip).supportsResources)
    }

    func test_resources() throws {
        // Given
        let temporaryPath = try temporaryPath()
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

    func test_targetDependencyBuildFilesPlatformFilter_when_iOS_targets_mac() {
        // Given
        let target = Target.test(deploymentTarget: .iOS("14.0", [.mac], supportsMacDesignedForIOS: false))

        // When
        let got = target.targetDependencyBuildFilesPlatformFilter

        // Then
        XCTAssertEqual(got, .catalyst)
    }

    func test_targetDependencyBuildFilesPlatformFilter_when_iOS_and_doesnt_target_mac() {
        // Given
        let target = Target.test(deploymentTarget: .iOS("14.0", [.iphone], supportsMacDesignedForIOS: false))

        // When
        let got = target.targetDependencyBuildFilesPlatformFilter

        // Then
        XCTAssertEqual(got, .ios)
    }
}
