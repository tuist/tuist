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
        subject = nil
        super.tearDown()
    }

    func test_save() throws {
        // Given
        let root = try temporaryPath()
        let graph = TuistGraph.DependenciesGraph.test()

        // When
        try subject.save(graph, to: root)

        // Then
        let graphPath = root.appending(components: "Tuist", "Dependencies", "graph.json")
        XCTAssertTrue(fileHandler.exists(graphPath))
    }

    func test_load() throws {
        // Given
        let root = try temporaryPath()

        let dependenciesPath = root.appending(components: "Tuist", "Dependencies.swift")
        try fileHandler.touch(dependenciesPath)

        try fileHandler.write(TuistGraph.DependenciesGraph.testDependenciesFile, path: dependenciesPath, atomically: true)

        let graphPath = root.appending(components: "Tuist", "Dependencies", "graph.json")
        try fileHandler.touch(graphPath)

        try fileHandler.write(TuistGraph.DependenciesGraph.testJson, path: graphPath, atomically: true)

        // When
        let got = try subject.load(at: root)

        // Then
        let expected = TuistGraph.DependenciesGraph(
            externalDependencies: [
                .iOS: ["RxSwift": [.xcframework(path: "/Tuist/Dependencies/Carthage/RxSwift.xcframework")]],
            ],
            externalProjects: [:]
        )

        XCTAssertEqual(got, expected)
    }

    func test_load_failed() throws {
        // Given
        let root = try temporaryPath()

        let dependenciesPath = root.appending(components: "Tuist", "Dependencies.swift")
        try fileHandler.touch(dependenciesPath)

        try fileHandler.write(TuistGraph.DependenciesGraph.testDependenciesFile, path: dependenciesPath, atomically: true)

        let graphPath = root.appending(components: "Tuist", "Dependencies", "graph.json")
        try fileHandler.touch(graphPath)

        try fileHandler.write(
            """
            {
              "externalDependencies": {},
              "externalProjects": [
                "ProjectPath",
                {
                  "invalid": "Project"
                }
              ]
            }
            """,
            path: graphPath,
            atomically: true
        )

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.load(at: root),
            DependenciesGraphControllerError.failedToDecodeDependenciesGraph
        )
    }

    func test_load_without_fetching() throws {
        // Given
        let root = try temporaryPath()

        let dependenciesPath = root.appending(components: "Tuist", "Dependencies.swift")
        try fileHandler.touch(dependenciesPath)

        try fileHandler.write(TuistGraph.DependenciesGraph.testDependenciesFile, path: dependenciesPath, atomically: true)

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.load(at: root),
            DependenciesGraphControllerError.dependenciesWerentFetched
        )
    }

    func test_load_no_dependencies() throws {
        // Given
        let root = try temporaryPath()
        let dependenciesPath = root.appending(components: "Tuist")
        try fileHandler.touch(dependenciesPath)

        // When / Then
        XCTAssertEqual(try subject.load(at: root), .none)
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
