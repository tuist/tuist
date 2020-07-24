import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class ValueGraphTraverserTests: TuistUnitTestCase {
    func test_directTargetDependencies() {
        // Given
        // A -> B -> C
        let project = Project.test()
        let a = Target.test(name: "A")
        let b = Target.test(name: "B")
        let c = Target.test(name: "C")
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: a.name, path: project.path): Set([.target(name: b.name, path: project.path)]),
            .target(name: b.name, path: project.path): Set([.target(name: c.name, path: project.path)]),
        ]
        let targets: [AbsolutePath: [String: Target]] = [project.path: [
            a.name: a,
            b.name: b,
            c.name: c,
        ]]
        let graph = ValueGraph.test(path: project.path,
                                    projects: [project.path: project],
                                    targets: targets,
                                    dependencies: dependencies)
        let subject = ValueGraphTraverser(graph: graph)

        // When
        let got = subject.directTargetDependencies(path: project.path, name: a.name)

        // Then
        XCTAssertEqual(got, [b])
    }
}
