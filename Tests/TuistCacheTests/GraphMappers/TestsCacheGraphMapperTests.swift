//import Foundation
//import TSCBasic
//import TuistCore
//import TuistGraph
//import XCTest
//
//@testable import TuistCache
//@testable import TuistCacheTesting
//@testable import TuistCoreTesting
//@testable import TuistGraphTesting
//@testable import TuistSupportTesting
//
//final class TestsCacheMapperTests: TuistUnitTestCase {
//    private var testsCacheDirectory: AbsolutePath!
//    private var testsGraphContentHasher: MockTestsGraphContentHasher!
//    private var subject: TestsCacheGraphMapper!
//
//    override func setUpWithError() throws {
//        try super.setUpWithError()
//        testsCacheDirectory = try temporaryPath()
//        testsGraphContentHasher = MockTestsGraphContentHasher()
//        subject = TestsCacheGraphMapper(
//            testsCacheDirectory: testsCacheDirectory,
//            testsGraphContentHasher: testsGraphContentHasher
//        )
//    }
//
//    override func tearDown() {
//        testsCacheDirectory = nil
//        testsGraphContentHasher = nil
//        subject = nil
//        super.tearDown()
//    }
//    
//    func test_map() throws {
//        let project = Project.test()
//        let frameworkA = TargetNode.test(
//            project: project,
//            target: Target.test(
//                name: "FrameworkA"
//            )
//        )
//        let unitTestsA = TargetNode.test(
//            project: project,
//            target: Target.test(
//                name: "UnitTestsA",
//                dependencies: [
//                    .target(name: "FrameworkA")
//                ]
//            ),
//            dependencies: [
//                frameworkA
//            ]
//        )
//        
//        let workspace = Workspace.test(
//            schemes: [
//                Scheme.test(
//                    name: "SchemeA",
//                    testAction: TestAction.test(
//                        targets: [
//                            TestableTarget(
//                                target: TargetReference(
//                                    projectPath: project.path,
//                                    name: unitTestsA.name
//                                )
//                            ),
//                        ]
//                    )
//                )
//            ]
//        )
//        
//        let graph = Graph.test(
//            workspace: workspace,
//            projects: [project],
//            targets: [
//                project.path: [
//                    frameworkA,
//                    unitTestsA,
//                ]
//            ]
//        )
//        
//        testsGraphContentHasher.contentHashesStub = {
//            $0.allTargets().reduce(into: [:]) { acc, target in
//                acc[target] = target.target.name
//            }
//        }
//        
//        try fileHandler.touch(
//            environment.testsCacheDirectory.appending(component: "FrameworkA")
//        )
//        try fileHandler.touch(
//            environment.testsCacheDirectory.appending(component: "UnitTestsA")
//        )
//        
//        let expectedGraph = Graph.test(
//            workspace: Workspace.test(
//                schemes: []
//            ),
//            projects: [project],
//            targets: [
//                project.path: [
//                    frameworkA,
//                    unitTestsA,
//                ]
//            ]
//        )
//        
//        // When
//        let (gotGraph, gotSideEffects) = try subject.map(graph: graph)
//        XCTAssertEqual(
//            gotGraph,
//            expectedGraph
//        )
//        XCTAssertEqual(
//            gotSideEffects,
//            [
//                .file(
//                    testsCacheDirectory.appending(component: "FrameworkA")
//                ),
//                .file(
//                    testsCacheDirectory.appending(component: "UnitTestsA"),
//                ),
//            ]
//        )
//    }
//}
