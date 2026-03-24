import Foundation
import Mockable
import Testing
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistHasher

struct PlatformConditionContentHasherTests {
    let subject: PlatformConditionContentHasher
    init() throws {
        subject = PlatformConditionContentHasher(contentHasher: ContentHasher())
    }

    @Test
    func test_hash() throws {
        // Given
        let platformCondition = try #require(PlatformCondition.when(Set([.macos])))

        // When
        let node = try subject.hash(identifier: "compilationCondition", platformCondition: platformCondition)

        // Then
        #expect(node == MerkleNode(
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
