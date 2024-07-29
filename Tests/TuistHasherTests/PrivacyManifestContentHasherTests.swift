import Foundation
import Path
import TuistCore
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest
@testable import TuistHasher

final class PrivacyManifestContentHasherTests: TuistUnitTestCase {
    private var subject: PrivacyManifestContentHasher!

    override func setUp() {
        super.setUp()
        subject = PrivacyManifestContentHasher(contentHasher: ContentHasher())
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_hash_isDeterministic() throws {
        // Given
        let privacyManifest = PrivacyManifest(
            tracking: true,
            trackingDomains: ["io.tuist"],
            collectedDataTypes: [["test": .string("tuist")]],
            accessedApiTypes: [["test": .string("tuist")]]
        )
        var results: Set<String> = Set()

        // When
        for _ in 0 ... 100 {
            results.insert(try subject.hash(privacyManifest))
        }

        // Then
        XCTAssertEqual(results.count, 1)
    }
}
