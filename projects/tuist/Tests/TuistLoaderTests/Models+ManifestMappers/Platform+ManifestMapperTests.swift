import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class PlatformManifestMapperTests: TuistUnitTestCase {
    func test_platform_iOS() throws {
        // Given
        let manifest: ProjectDescription.Platform = .iOS

        // When
        let model = try TuistGraph.Platform.from(manifest: manifest)

        // Then
        XCTAssertEqual(model, .iOS)
    }

    func test_platform_tvOS() throws {
        // Given
        let manifest: ProjectDescription.Platform = .tvOS

        // When
        let model = try TuistGraph.Platform.from(manifest: manifest)

        // Then
        XCTAssertEqual(model, .tvOS)
    }

    func test_platform_macOS() throws {
        // Given
        let manifest: ProjectDescription.Platform = .macOS

        // When
        let model = try TuistGraph.Platform.from(manifest: manifest)

        // Then
        XCTAssertEqual(model, .macOS)
    }

    func test_platform_watchOS() throws {
        // Given
        let manifest: ProjectDescription.Platform = .watchOS

        // When
        let model = try TuistGraph.Platform.from(manifest: manifest)

        // Then
        XCTAssertEqual(model, .watchOS)
    }
}
