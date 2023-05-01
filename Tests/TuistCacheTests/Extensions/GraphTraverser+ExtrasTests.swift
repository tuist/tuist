import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest
@testable import TuistCache

class GraphTraverserExtrasTests: XCTestCase {
    func test_filterIncludedTargets_includeExcluded() throws {
        // Given
        let app = Target.test(name: "App", product: .app)
        let tests1 = Target.test(name: "AppTests1", product: .unitTests)
        let tests2 = Target.test(name: "AppTests2", product: .unitTests)
        let tests3 = Target.test(name: "AppTests3", product: .unitTests)
        let project = Project.test(
            path: "/path/a"
        )

        // Given: Value Graph
        let testDependencies: Set<GraphDependency> = [
            .target(name: app.name, path: project.path)
        ]
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: project.path): [],
            .target(name: tests1.name, path: project.path): testDependencies,
            .target(name: tests2.name, path: project.path): testDependencies,
            .target(name: tests3.name, path: project.path): testDependencies,
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                tests1.name: tests1,
                tests2.name: tests2,
                tests3.name: tests3,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        var filteredTargets: Set<GraphTarget>
        // When
        filteredTargets = subject.filterIncludedTargets(
            basedOn: subject.allTargets(),
            testPlan: nil,
            includedTargets: [tests1.name],
            excludedTargets: []
        )

        // Then
        XCTAssertEqual(filteredTargets.map(\.target), [tests1])

        // When
        filteredTargets = subject.filterIncludedTargets(
            basedOn: subject.allTargets(),
            testPlan: nil,
            includedTargets: [tests1.name],
            excludedTargets: [tests1.name]
        )

        // Then
        XCTAssertEqual(filteredTargets.map(\.target), [tests1])

        // When
        filteredTargets = subject.filterIncludedTargets(
            basedOn: subject.allTargets(),
            testPlan: nil,
            includedTargets: [],
            excludedTargets: [tests1.name]
        )

        // Then
        XCTAssertEqual(Set(filteredTargets.map(\.target.name)), [app.name, tests2.name, tests3.name])

        // When
        filteredTargets = subject.filterIncludedTargets(
            basedOn: subject.allTargets(),
            testPlan: nil,
            includedTargets: [tests1.name],
            excludedTargets: [tests2.name]
        )

        // Then
        XCTAssertEqual(Set(filteredTargets.map(\.target)), [tests1])
    }

    func test_filterIncudedTargets_testPlan() throws {
        // Given
        let app = Target.test(name: "App", product: .app)
        let tests1 = Target.test(name: "AppTests1", product: .unitTests)
        let tests2 = Target.test(name: "AppTests2", product: .unitTests)
        let tests3 = Target.test(name: "AppTests3", product: .unitTests)
        let tests4 = Target.test(name: "AppTests4", product: .unitTests)
        let projectPath: AbsolutePath = "/path/a"

        let testPlan = TestPlan(
            path: "/path/test.xctestplan",
            testTargets: [
                .init(target: tests1, projectPath: projectPath),
                .init(target: tests3, projectPath: projectPath, isEnabled: false),
                .init(target: tests4, projectPath: projectPath),
            ],
            isDefault: true
        )
        let testAction = TestAction.test(testPlans: [testPlan])
        let testScheme = Scheme.test(testAction: testAction)
        let project = Project.test(
            path: projectPath,
            schemes: [testScheme]
        )

        // Given: Value Graph
        let testDependencies: Set<GraphDependency> = [
            .target(name: app.name, path: project.path)
        ]
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: project.path): [],
            .target(name: tests1.name, path: project.path): testDependencies,
            .target(name: tests2.name, path: project.path): testDependencies,
            .target(name: tests3.name, path: project.path): testDependencies,
            .target(name: tests4.name, path: project.path): testDependencies,
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [project.path: [
                app.name: app,
                tests1.name: tests1,
                tests2.name: tests2,
                tests3.name: tests3,
                tests4.name: tests4,
            ]],
            dependencies: dependencies
        )
        let subject = GraphTraverser(graph: graph)

        var filteredTargets: Set<GraphTarget>
        // When
        filteredTargets = subject.filterIncludedTargets(
            basedOn: subject.allTargets(),
            testPlan: testPlan.name,
            includedTargets: [],
            excludedTargets: []
        )

        // Then
        XCTAssertEqual(filteredTargets.map(\.target), [tests1, tests4])
    }
}

extension TestPlan.TestTarget {
    fileprivate init(target: Target, projectPath: AbsolutePath, isEnabled: Bool = true) {
        self.init(
            target: TargetReference(projectPath: projectPath, name: target.name),
            isEnabled: isEnabled
        )
    }
}
