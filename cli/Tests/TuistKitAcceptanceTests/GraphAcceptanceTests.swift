// TODO: Fix (issues with finding executables)
// final class GraphAcceptanceTestiOSWorkspaceWithMicrofeatureArchitecture: TuistAcceptanceTestCase {
//    func test_ios_workspace_with_microfeature_architecture() async throws {
//        try await setUpFixture("ios_workspace_with_microfeature_architecture")
//        try await run(GraphCommand.self, "--output-path", fixturePath.pathString)
//        let graphFile = fixturePath.appending(component: "graph.png")
//        try await CommandRunner().run(arguments: [
//            "file",
//            graphFile.pathString,
//        ]).pipedStream().awaitCompletion()
//        try FileHandler.shared.delete(graphFile)
//
//        try await run(GraphCommand.self, "--output-path", fixturePath.pathString, "Data")
//        try await CommandRunner().run(arguments: [
//            "file",
//            graphFile.pathString,
//        ]).pipedStream().awaitCompletion()
//    }
// }
