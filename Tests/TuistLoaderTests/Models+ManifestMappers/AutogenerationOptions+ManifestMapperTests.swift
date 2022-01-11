import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class AutogenerationOptionsManifestMapperTests: TuistUnitTestCase {
    private typealias Manifest = ProjectDescription.Config.GenerationOptions.AutogenerationOptions

    func test_from_returnsTheCorrectValue_whenManifestIncludesAllOptions() throws {
        // Given
        let manifest: Manifest = .enabled([.parallelizable, .randomExecutionOrdering])

        // When
        let got = try TuistGraph.AutogenerationOptions.from(manifest: manifest)

        // Then
        XCTAssertEqual(.enabled([.parallelizable, .randomExecutionOrdering]), got)
    }

    func test_from_returnsTheCorrectValue_whenManifestIsEmpty() throws {
        // Given
        let manifest: Manifest = .enabled([])

        // When
        let got = try TuistGraph.AutogenerationOptions.from(manifest: manifest)

        // Then
        XCTAssertEqual(.enabled([]), got)
    }
}
