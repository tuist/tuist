import Foundation
import Testing
import XCTest
@testable import TuistCore

final class TestIdentifierTests: XCTestCase {
    func test_should_failToInitialize_when_targetEmpty_usingIndividualComponents() throws {
        try XCTAssertThrowsError(TestIdentifier(target: ""))
    }

    func test_should_failToInitialize_when_classEmpty_usingIndividualComponents() throws {
        try XCTAssertThrowsError(TestIdentifier(target: "target", class: ""))
    }

    func test_should_failToInitialize_when_methodEmpty_usingIndividualComponents() throws {
        try XCTAssertThrowsError(TestIdentifier(target: "target", class: "class", method: ""))
    }

    func test_should_initialize_when_targetSpecified_usingIndividualComponents() throws {
        let testIdentifier = try TestIdentifier(target: "target")
        XCTAssertEqual(testIdentifier.description, "target")
    }

    func test_should_initialize_when_targetClassSpecified_usingIndividualComponents() throws {
        let testIdentifier = try TestIdentifier(target: "target", class: "class")
        XCTAssertEqual(testIdentifier.description, "target/class")
    }

    func test_should_initialize_when_targetClassMethodSpecified_usingIndividualComponents() throws {
        let testIdentifier = try TestIdentifier(target: "target", class: "class", method: "method")
        XCTAssertEqual(testIdentifier.description, "target/class/method")
    }

    func test_should_failToInitialize_when_targetEmpty_usingString() throws {
        try XCTAssertThrowsError(TestIdentifier(string: ""))
    }

    func test_should_failToInitialize_when_classEmpty_usingString() throws {
        try XCTAssertThrowsError(TestIdentifier(string: "target/"))
    }

    func test_should_failToInitialize_when_methodEmpty_usingString() throws {
        try XCTAssertThrowsError(TestIdentifier(string: "target/class/"))
    }

    func test_should_failToInitialize_when_targetMethodSpecifiedButNotClass_usingString() {
        try XCTAssertThrowsError(TestIdentifier(string: "target//method"))
    }

    func test_should_initialize_when_targetSpecified_usingString() throws {
        let testIdentifier = try TestIdentifier(string: "target")
        XCTAssertEqual(testIdentifier.description, "target")
    }

    func test_should_initialize_when_targetClassSpecified_usingString() throws {
        let testIdentifier = try TestIdentifier(string: "target/class")
        XCTAssertEqual(testIdentifier.description, "target/class")
    }

    func test_should_initialize_when_targetClassMethodSpecified_usingString() throws {
        let testIdentifier = try TestIdentifier(target: "target/class/method")
        XCTAssertEqual(testIdentifier.description, "target/class/method")
    }
}

struct TestTargetQueryTests {
    @Test(arguments: [
        ("tag:snapshot", ["FeatureATests", "FeatureBTests"]),
        ("tag:snapshot/Suite", ["FeatureATests/Suite", "FeatureBTests/Suite"]),
        ("tag:snapshot/Suite/testView", ["FeatureATests/Suite/testView", "FeatureBTests/Suite/testView"]),
        ("tag:slow", ["FeatureBTests"]),
        ("tag:missing", []),
        ("FeatureATests/Suite/testView", ["FeatureATests/Suite/testView"]),
    ])
    func resolvesTargetQueries(query: String, expected: [String]) throws {
        let targetTags: [String: Set<String>] = [
            "FeatureBTests": ["snapshot", "slow"],
            "LogicTests": [],
            "FeatureATests": ["snapshot"],
            "AlmostSnapshotTests": ["snapshots"],
        ]
        let resolved = try TestIdentifier(string: query).resolvingTargetQuery(targetTags: targetTags)
        #expect(resolved.map(\.description) == expected)
    }

    @Test
    func legacyTestProductsPreserveNamedFiltersAndRejectTagQueries() throws {
        let data = Data(#"{"testTargetHashes":{"FeatureTests":"hash"}}"#.utf8)
        let graph = try JSONDecoder().decode(SelectiveTestingGraph.self, from: data)
        let identifier = try TestIdentifier(string: "FeatureTests/Suite/testView")
        #expect(try identifier.resolvingTargetQuery(targetTags: graph.testTargetTags) == [identifier])
        #expect(throws: TestIdentifier.Error.self) {
            try TestIdentifier(string: "tag:snapshot").resolvingTargetQuery(targetTags: graph.testTargetTags)
        }
    }

    @Test
    func productTagsSurviveSerialization() throws {
        let graph = SelectiveTestingGraph(
            testTargetHashes: ["FeatureTests": "hash"],
            attemptedTestPlans: ["Snapshots"],
            requestedTestIdentifiers: ["FeatureTests/Suite"],
            testTargetTags: ["FeatureTests": ["snapshot", "slow"]]
        )
        let restored = try JSONDecoder().decode(SelectiveTestingGraph.self, from: JSONEncoder().encode(graph))
        let resolved = try TestIdentifier(string: "tag:snapshot").resolvingTargetQuery(targetTags: restored.testTargetTags)
        #expect(resolved.map(\.description) == ["FeatureTests"])
        #expect(restored.testTargetHashes == ["FeatureTests": "hash"])
        #expect(restored.attemptedTestPlans == ["Snapshots"])
        #expect(restored.requestedTestIdentifiers == ["FeatureTests/Suite"])
    }
}
