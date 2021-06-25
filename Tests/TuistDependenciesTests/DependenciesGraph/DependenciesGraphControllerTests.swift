import Foundation
import TSCBasic
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistDependenciesTesting
@testable import TuistGraphTesting
@testable import TuistSupportTesting

public final class DependenciesGraphControllerTests: TuistUnitTestCase {
    private var subject: DependenciesGraphController!

    override public func setUp() {
        super.setUp()

        subject = DependenciesGraphController()
    }

    override public func tearDown() {
        super.tearDown()

        subject = nil
    }

    func test_save() throws {
        // Given
        let root = try temporaryPath()
        let graph = DependenciesGraph.test()

        // When
        try subject.save(graph, to: root)

        // Then
        let graphPath = root.appending(components: "Tuist", "Dependencies", "graph.json")
        XCTAssertTrue(fileHandler.exists(graphPath))
    }

    func test_load() throws {
        // Given
        let root = try temporaryPath()
        let graphPath = root.appending(components: "Tuist", "Dependencies", "graph.json")
        try fileHandler.touch(graphPath)

        try fileHandler.write(DependenciesGraph.testJson, path: graphPath, atomically: true)

        // When
        let got = try subject.load(at: root)

        // Then
        let expected = DependenciesGraph.test(
            thirdPartyDependencies: [
                "RxSwift": .xcframework(
                    path: "/Tuist/Dependencies/Carthage/RxSwift.xcframework"
                ),
            ]
        )

        XCTAssertEqual(got, expected)
    }

    func test_clean() throws {
        // Given
        let root = try temporaryPath()
        let graphPath = root.appending(components: "Tuist", "Dependencies", "graph.json")
        try fileHandler.touch(graphPath)

        // When
        try subject.clean(at: root)

        // Then
        XCTAssertFalse(fileHandler.exists(graphPath))
    }
}
