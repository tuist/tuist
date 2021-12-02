import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class TargetManifestMapperErrorTests: TuistUnitTestCase {
    func test_description_when_invalidResourcesGlob() {
        // Given
        let invalidGlobs: [InvalidGlob] = [.init(pattern: "/path/**/*", nonExistentPath: "/path/")]
        let subject = TargetManifestMapperError.invalidResourcesGlob(targetName: "Target", invalidGlobs: invalidGlobs)

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(
            got,
            "The target Target has the following invalid resource globs:\n" + invalidGlobs.invalidGlobsDescription
        )
    }
}
