import TuistCore
import TuistLoader
import TuistSupport
import XcodeProj
import FileSystemTesting
import Testing

@testable import TuistGenerator
@testable import TuistSupport
@testable import TuistTesting

struct TuistGeneratorPerformanceTests {

    // MARK: - Tests

    @Test(.inTemporaryDirectory)
    func test_generateWorkspace_performance() async throws {
        guard !isRunningInDebug() else {
            return
        }

        // Given
        let subject = DescriptorGenerator()
        let config = TestModelGenerator.WorkspaceConfig(
            projects: 50,
            testTargets: 5,
            frameworkTargets: 5,
            schemes: 10,
            sources: 200,
            resources: 100,
            headers: 100
        )
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let modelGenerator = TestModelGenerator(rootPath: temporaryPath, config: config)
        let graph = try await modelGenerator.generate()

        let graphTraverser = GraphTraverser(graph: graph)
        _ = try await subject.generateWorkspace(graphTraverser: graphTraverser)
    }

    // MARK: - Helpers

    private func isRunningInDebug() -> Bool {
        #if DEBUG
            return true
        #else
            return false
        #endif
    }
}
