import Foundation
import TSCBasic
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class CircularDependencyLinterTests: TuistUnitTestCase {
    // MARK: - Dependency Cycle

    func test_loadWorkspace_differentProjectDependencyCycle() throws {
        // Given
        let targetA = Target.test(name: "A", dependencies: [.project(target: "B", path: "/B")])
        let targetB = Target.test(name: "B", dependencies: [.project(target: "C", path: "/C")])
        let targetC = Target.test(name: "C", dependencies: [.project(target: "A", path: "/A")])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA])
        let projectB = Project.test(path: "/B", name: "B", targets: [targetB])
        let projectC = Project.test(path: "/C", name: "C", targets: [targetC])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A", "/B", "/C"])
        let subject = CircularDependencyLinter()

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.lintWorkspace(
                workspace: workspace,
                projects: [
                    projectA,
                    projectB,
                    projectC,
                ]
            ),
            GraphLoadingError.circularDependency([
                .init(path: "/A", name: "A"),
                .init(path: "/B", name: "B"),
                .init(path: "/C", name: "C"),
            ])
        )
    }

    func test_loadWorkspace_crossProjectsReferenceWithNoDependencyCycle() throws {
        // Given
        let targetA1 = Target.test(name: "A1", dependencies: [.project(target: "B1", path: "/B")])
        let targetA2 = Target.test(name: "A2", dependencies: [.project(target: "B2", path: "/B")])
        let targetB1 = Target.test(name: "B1", dependencies: [.project(target: "C", path: "/C")])
        let targetB2 = Target.test(name: "B2", dependencies: [])
        let targetC = Target.test(name: "C", dependencies: [.project(target: "A2", path: "/A")])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA1, targetA2])
        let projectB = Project.test(path: "/B", name: "B", targets: [targetB1, targetB2])
        let projectC = Project.test(path: "/C", name: "C", targets: [targetC])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A", "/B", "/C"])
        let subject = CircularDependencyLinter()

        // When / Then
        XCTAssertNoThrow(
            try subject.lintWorkspace(
                workspace: workspace,
                projects: [
                    projectA,
                    projectB,
                    projectC,
                ]
            )
        )
    }

    func test_loadWorkspace_crossProjectsReferenceWithDependencyCycle() throws {
        // Given
        let targetA1 = Target.test(name: "A1", dependencies: [.project(target: "B1", path: "/B")])
        let targetA2 = Target.test(name: "A2", dependencies: [.project(target: "B2", path: "/B")])
        let targetB1 = Target.test(name: "B1", dependencies: [.project(target: "C1", path: "/C")])
        let targetB2 = Target.test(name: "B2", dependencies: [.project(target: "C2", path: "/C")])
        let targetC1 = Target.test(name: "C1", dependencies: [.project(target: "A2", path: "/A")])
        let targetC2 = Target.test(name: "C2", dependencies: [.project(target: "B1", path: "/B")])
        let projectA = Project.test(path: "/A", name: "A", targets: [targetA1, targetA2])
        let projectB = Project.test(path: "/B", name: "B", targets: [targetB1, targetB2])
        let projectC = Project.test(path: "/C", name: "C", targets: [targetC1, targetC2])
        let workspace = Workspace.test(path: "/", name: "Workspace", projects: ["/A", "/B", "/C"])
        let subject = CircularDependencyLinter()

        // When / Then
        XCTAssertThrowsError(
            try subject.lintWorkspace(
                workspace: workspace,
                projects: [
                    projectA,
                    projectB,
                    projectC,
                ]
            )
        ) { error in
            // need to manually inspect the error as depending on traversal order may result in different nodes getting listed
            let graphError = error as? GraphLoadingError
            XCTAssertNotNil(graphError)
            XCTAssertTrue(graphError?.isCycleError == true)
        }
    }
}

extension GraphLoadingError {
    fileprivate var isCycleError: Bool {
        switch self {
        case .circularDependency:
            return true
        default:
            return false
        }
    }
}
