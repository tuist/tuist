import Foundation
import Mockable
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
import XCTest

@testable import TuistHasher

final class PlatformConditionContentHasherTests: TuistUnitTestCase {
    var subject: PlatformConditionContentHasher!

    override func setUp() async throws {
        try await super.setUp()
        subject = PlatformConditionContentHasher(contentHasher: ContentHasher())
    }

    override func tearDown() async throws {
        subject = nil
        try await super.tearDown()
    }

    func test_hash() throws {
        // Given
        let platformCondition = try XCTUnwrap(PlatformCondition.when(Set([.macos])))

        // When
        let node = try subject.hash(identifier: "compilationCondition", platformCondition: platformCondition)

        // Then
        XCTAssertEqual(node, MerkleNode(
            hash: "4ed91b7e02b960dc31256de17f3f131f",
            identifier: "compilationCondition",
            children: [
                MerkleNode(
                    hash: "43b9d8ea18c48c3a64c4e37338fc668f",
                    identifier: "macos",
                    children: []
                ),
            ]
        ))
    }
}
