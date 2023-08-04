import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest
@testable import TuistCache

class GraphTraverserExtrasTests: XCTestCase {
    private var app: Target!
    private var tests1: Target!
    private var tests2: Target!
    private var tests3: Target!
    private var tests4: Target!
    private var testPlan: TestPlan!

    private var graphTraverserWithoutTestPlans: GraphTraverser!
    private var graphTraverserWithTestPlan: GraphTraverser!
    private var graphTraverserWithExternalTargets: GraphTraverser!

    override func setUp() {
        super.setUp()

        let projectPath: AbsolutePath = "/path/a"

        app = Target.test(name: "App", product: .app)
        tests1 = Target.test(name: "AppTests1", product: .unitTests)
        tests2 = Target.test(name: "AppTests2", product: .unitTests)
        tests3 = Target.test(name: "AppTests3", product: .unitTests)
        tests4 = Target.test(name: "AppTests4", product: .unitTests)
        tests4 = Target.test(name: "AppTests4", product: .unitTests)

        let projectWithoutTestPlans = Project.test(path: projectPath)

        let testDependencies: Set<GraphDependency> = [
            .target(name: app.name, path: projectPath)
        ]
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: projectPath): [],
            .target(name: tests1.name, path: projectPath): testDependencies,
            .target(name: tests2.name, path: projectPath): testDependencies,
            .target(name: tests3.name, path: projectPath): testDependencies,
            .target(name: tests4.name, path: projectPath): testDependencies,
        ]
        let graphWithoutTestPlans = Graph.test(
            projects: [projectPath: projectWithoutTestPlans],
            targets: [projectPath: [
                app.name: app,
                tests1.name: tests1,
                tests2.name: tests2,
                tests3.name: tests3,
                tests4.name: tests4,
            ]],
            dependencies: dependencies
        )
        graphTraverserWithoutTestPlans = GraphTraverser(graph: graphWithoutTestPlans)

        testPlan = TestPlan(
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
        let projectWithTestPlan = Project.test(
            path: projectPath,
            schemes: [testScheme]
        )

        let graphWithTestPlan = Graph.test(
            projects: [projectPath: projectWithTestPlan],
            targets: [projectPath: [
                app.name: app,
                tests1.name: tests1,
                tests2.name: tests2,
                tests3.name: tests3,
                tests4.name: tests4,
            ]],
            dependencies: dependencies
        )
        graphTraverserWithTestPlan = GraphTraverser(graph: graphWithTestPlan)

        let externalProjectPath: AbsolutePath = "/path/b"
        let externalProject = Project.test(
            path: externalProjectPath,
            isExternal: true
        )

        let graphWithExternalTargets = Graph.test(
            projects: [
                projectPath: projectWithoutTestPlans,
                externalProjectPath: externalProject,
            ],
            targets: [
                projectPath: [
                    app.name: app,
                    tests1.name: tests1,
                    tests2.name: tests2,
                ],
                externalProjectPath: [
                    tests3.name: tests3,
                    tests4.name: tests4,
                ]
            ],
            dependencies: dependencies
        )
        graphTraverserWithExternalTargets = GraphTraverser(graph: graphWithExternalTargets)
    }

    func test_filterIncludedTargets_when_graphHasNoTestPlans_includeSpecificTarget() throws {
        // When
        let filteredTargets = graphTraverserWithoutTestPlans.filterIncludedTargets(
            basedOn: graphTraverserWithoutTestPlans.allTargets(),
            testPlan: nil,
            includedTargets: [tests1.name],
            excludedTargets: []
        )

        // Then
        XCTAssertEqual(filteredTargets.map(\.target), [tests1])
    }

    func test_filterIncludedTargets_when_graphHasNoTestPlans_includePriorityOverExclude() throws {
        // When
        let filteredTargets = graphTraverserWithoutTestPlans.filterIncludedTargets(
            basedOn: graphTraverserWithoutTestPlans.allTargets(),
            testPlan: nil,
            includedTargets: [tests1.name],
            excludedTargets: [tests1.name]
        )

        // Then
        XCTAssertEqual(filteredTargets.map(\.target), [tests1])
    }

    func test_filterIncludedTargets_when_graphHasNoTestPlans_filtersOnlyExcludedWhenSpecified() throws {
        // When
        let filteredTargets = graphTraverserWithoutTestPlans.filterIncludedTargets(
            basedOn: graphTraverserWithoutTestPlans.allTargets(),
            testPlan: nil,
            includedTargets: [],
            excludedTargets: [tests1.name]
        )

        // Then
        XCTAssertEqual(Set(filteredTargets.map(\.target.name)), [app.name, tests2.name, tests3.name, tests4.name])
    }

    func test_filterIncludedTargets_when_graphHasNoTestPlans_excludedIgnoredWhenIncludedSpecified() throws {
        // When
        let filteredTargets = graphTraverserWithoutTestPlans.filterIncludedTargets(
            basedOn: graphTraverserWithoutTestPlans.allTargets(),
            testPlan: nil,
            includedTargets: [tests1.name],
            excludedTargets: [tests2.name]
        )

        // Then
        XCTAssertEqual(Set(filteredTargets.map(\.target)), [tests1])
    }

    func test_filterIncludedTargets_when_graphHasNoTestPlans_excludeExternalTargets() throws {
        // When
        let filteredTargets = graphTraverserWithExternalTargets.filterIncludedTargets(
            basedOn: graphTraverserWithoutTestPlans.allTargets(),
            testPlan: nil,
            includedTargets: [],
            excludedTargets: [],
            excludingExternalTargets: true
        )

        // Then
        XCTAssertEqual(Set(filteredTargets.map(\.target)), [tests1, tests2])
    }

    func test_filterIncludedTargets_when_graphHasTestPlan_filtersOnlyTestPlanTargets() throws {
        var filteredTargets: Set<GraphTarget>
        // When
        filteredTargets = graphTraverserWithTestPlan.filterIncludedTargets(
            basedOn: graphTraverserWithTestPlan.allTargets(),
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
