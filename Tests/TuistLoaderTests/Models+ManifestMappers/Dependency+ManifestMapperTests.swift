import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class DependencyManifestMapperTests: TuistUnitTestCase {
    func test_from_when_cocoapods() throws {
        // Given
        let dependency = TargetDependency.cocoapods(path: "./path/to/project")
        let generatorPaths = GeneratorPaths(manifestDirectory: AbsolutePath("/"))

        // When
        let got = try TuistCore.Dependency.from(manifest: dependency, generatorPaths: generatorPaths)

        // Then
        guard case let .cocoapods(path) = got else {
            XCTFail("Dependency should be cocoapods")
            return
        }
        XCTAssertEqual(path, AbsolutePath("/path/to/project"))
    }

    func test_from_when_localPackage() throws {
        // Given
        let dependency = TargetDependency.package(product: "library")
        let generatorPaths = GeneratorPaths(manifestDirectory: AbsolutePath("/"))

        // When
        let got = try TuistCore.Dependency.from(manifest: dependency, generatorPaths: generatorPaths)

        // Then
        guard
            case let .package(product, type: productType) = got
        else {
            XCTFail("Dependency should be package")
            return
        }
        XCTAssertEqual(product, "library")
        XCTAssertEqual(productType, .staticLibrary)
    }
}
