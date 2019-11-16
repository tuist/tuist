import Basic
import Foundation
import TuistCore
import TuistGenerator
import TuistSupport
import XCTest
@testable import TuistKit

final class ManifestTargetGeneratorTests: XCTestCase {
    func test_generateManifestTarget() throws {
        // Given
        let path = AbsolutePath("/test")
        let manifestLoader = MockGraphManifestLoader()
        manifestLoader.manifestPathStub = { _, _ in
            path.appending(component: "Project.swift")
        }
        manifestLoader.manifestsAtStub = { _ in
            Set([.project])
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
        XCTAssertEqual(target.name, "MyProject_Manifest")
        XCTAssertEqual(target.product, .staticFramework)
        XCTAssertEqual(target.sources.map { $0.path.pathString }, ["/test/Project.swift"])
        XCTAssertNil(target.infoPlist)
        assertValidManifestBuildSettings(for: target,
                                         expectedSearchPath: "/test")
    }

    func test_generateManifestTarget_containsAllManifestFiles() throws {
        // Given
        let path = AbsolutePath("/test")
        let manifestLoader = MockGraphManifestLoader()
        manifestLoader.manifestPathStub = { _, _ in
            path.appending(component: "Project.swift")
        }
        manifestLoader.manifestsAtStub = { _ in
            Set([.project, .tuistConfig, .workspace, .setup])
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
        let sources = Set(target.sources.map { $0.path.pathString })
        XCTAssertEqual(sources, Set([
            "/test/Workspace.swift",
            "/test/Setup.swift",
            "/test/TuistConfig.swift",
            "/test/Project.swift",
        ]))
    }

    // MARK: - Helpers

    private func assertValidManifestBuildSettings(for target: Target,
                                                  expectedSearchPath: String) {
        guard let settings = target.settings else {
            XCTFail("Missing settings")
            return
        }

        XCTAssertEqual(settings.base["FRAMEWORK_SEARCH_PATHS"], .string(expectedSearchPath))
        XCTAssertEqual(settings.base["LIBRARY_SEARCH_PATHS"], .string(expectedSearchPath))
        XCTAssertEqual(settings.base["SWIFT_INCLUDE_PATHS"], .string(expectedSearchPath))
        XCTAssertEqual(settings.base["SWIFT_VERSION"], .string(Constants.swiftVersion))
    }
}
