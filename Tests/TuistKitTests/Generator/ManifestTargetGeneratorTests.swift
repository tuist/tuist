import Basic
import Foundation
import TuistCore
import XCTest
@testable import TuistKit

class ManifestTargetGeneratorTests: XCTestCase {
    func test_generateManifestTarget() throws {
        // Given
        let path = AbsolutePath("/test")
        let manifestLoader = MockGraphManifestLoader()
        manifestLoader.manifestPathStub = { _, _ in
            path.appending(component: "Project.swift")
        }
        let resourceLocator = MockResourceLocator()
        resourceLocator.projectDescriptionStub = {
            AbsolutePath("/test/ProjectDescription.dylib")
        }

        let subject = ManifestTargetGenerator(manifestLoader: manifestLoader,
                                              resourceLocator: resourceLocator)
        // When
        let target = try subject.generateManifestTarget(for: "MyProject", at: path)

        // Then
        XCTAssertEqual(target.name, "MyProject-Manifest")
        XCTAssertEqual(target.sources.map { $0.asString }, ["/test/Project.swift"])
        XCTAssertNil(target.infoPlist)
        assertValidManifestBuildSettings(for: target)
    }

    // MARK: - Helpers

    func assertValidManifestBuildSettings(for target: Target) {
        guard let settings = target.settings else {
            XCTFail("Missing settings")
            return
        }

        XCTAssertEqual(settings.base["FRAMEWORK_SEARCH_PATHS"], "/test")
        XCTAssertEqual(settings.base["LIBRARY_SEARCH_PATHS"], "/test")
        XCTAssertEqual(settings.base["SWIFT_FORCE_DYNAMIC_LINK_STDLIB"], "YES")
        XCTAssertEqual(settings.base["SWIFT_FORCE_STATIC_LINK_STDLIB"], "NO")
        XCTAssertEqual(settings.base["SWIFT_INCLUDE_PATHS"], "/test")
        XCTAssertEqual(settings.base["SWIFT_VERSION"], Constants.swiftVersion)
        XCTAssertEqual(settings.base["LD"], "/usr/bin/true")
        XCTAssertEqual(settings.base["SWIFT_ACTIVE_COMPILATION_CONDITIONS"], "SWIFT_PACKAGE")
        XCTAssertEqual(settings.base["OTHER_SWIFT_FLAGS"], "-swift-version 4 -I /test")
    }
}
