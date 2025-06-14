import TuistCore
import TuistLoader
import TuistSupport
import XcodeProj
import XCTest

@testable import TuistGenerator
@testable import TuistSupport
@testable import TuistTesting

final class TuistGeneratorPerformanceTests: TuistTestCase {
    override func setUp() {
        super.setUp()
    }

    // MARK: - Tests

    func test_generateWorkspace_performance() async throws {
        guard !isRunningInDebug() else {
            // Performance tests need to be run in Release Mode for more realistic results
            // Note: When we switch to Xcode11.5+ only on CI we can use `XCTSkipIf` instead of a guard statement
            //
            // XCTSkipIf(isRunningInDebug, "Performance tests need to be run in Release Mode for more realistic results")
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
        let temporaryPath = try temporaryPath()
        let modelGenerator = TestModelGenerator(rootPath: temporaryPath, config: config)
        let graph = try await modelGenerator.generate()

        measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
            // When
            startMeasuring()
            let graphTraverser = GraphTraverser(graph: graph)
            Task {
                do {
                    _ = try await subject.generateWorkspace(graphTraverser: graphTraverser)
                } catch {
                    XCTFail("Failed to generate workspace: \(error)")
                }
                stopMeasuring()
            }
        }
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
