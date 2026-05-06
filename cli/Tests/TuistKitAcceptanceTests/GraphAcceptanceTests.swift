// TODO: Fix (issues with finding executables)
// final class GraphAcceptanceTestiOSWorkspaceWithMicrofeatureArchitecture: TuistAcceptanceTestCase {
//    func test_ios_workspace_with_microfeature_architecture() async throws {
//        try await setUpFixture("ios_workspace_with_microfeature_architecture")
//        try await run(GraphCommand.self, "--output-path", fixturePath.pathString)
//        let graphFile = fixturePath.appending(component: "graph.png")
//        try CommandRunner().runAndPrint(
//            [
//                "file",
//                graphFile.pathString,
//            ]
//        )
//        try await FileSystem().remove(graphFile)
//
//        try await run(GraphCommand.self, "--output-path", fixturePath.pathString, "Data")
//        try CommandRunner().runAndPrint(
//            [
//                "file",
//                graphFile.pathString,
//            ]
//        )
//    }
// }
