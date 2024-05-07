import Foundation
import TuistGraph
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class CloudManifestMapperTests: TuistUnitTestCase {
    func test_removes_trailing_back_slash_if_present_in_url() throws {
        // When
        let got = try TuistGraph.Cloud.from(
            manifest: .cloud(
                projectId: "tuist/tuist",
                url: "https://cloud.tuist.io/"
            )
        )

        // Then
        XCTAssertEqual(
            got,
            .test(
                url: URL(string: "https://cloud.tuist.io")!,
                projectId: "tuist/tuist"
            )
        )
    }
}
