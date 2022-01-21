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
        let manifest: Manifest = .enabled(
            codeCoverageMode: .targets(["Target"]),
            testingOptions: [.parallelizable, .randomExecutionOrdering]
        )

        // When
        let got = try TuistGraph.AutogenerationOptions.from(manifest: manifest, generatorPaths: .init(manifestDirectory: .root))

        // Then
        XCTAssertEqual(
            got,
            .enabled(
                codeCoverageMode: .targets([.init(projectPath: .root, name: "Target")]),
                testingOptions: [.parallelizable, .randomExecutionOrdering]
            )
        )
    }

    func test_from_returnsTheCorrectValue_whenManifestIsEmpty() throws {
        // Given
        let manifest: Manifest = .enabled(codeCoverageMode: .disabled, testingOptions: [])

        // When
        let got = try TuistGraph.AutogenerationOptions.from(manifest: manifest, generatorPaths: .init(manifestDirectory: .root))

        // Then
        XCTAssertEqual(got, .enabled(codeCoverageMode: .disabled, testingOptions: []))
    }
}
