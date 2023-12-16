import TSCBasic
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest

// TODO: Fix (issues with finding executables)
// final class GraphAcceptanceTestiOSWorkspaceWithMicrofeatureArchitecture: TuistAcceptanceTestCase {
//    func test_ios_workspace_with_microfeature_architecture() async throws {
//        try setUpFixture("ios_workspace_with_microfeature_architecture")
//        try await run(GraphCommand.self, "--output-path", fixturePath.pathString)
//        let graphFile = fixturePath.appending(component: "graph.png")
//        try System.shared.runAndPrint(
//            [
//                "file",
//                graphFile.pathString,
//            ]
//        )
//        try FileHandler.shared.delete(graphFile)
//
//        try await run(GraphCommand.self, "--output-path", fixturePath.pathString, "Data")
//        try System.shared.runAndPrint(
//            [
//                "file",
//                graphFile.pathString,
//            ]
//        )
//    }
// }
