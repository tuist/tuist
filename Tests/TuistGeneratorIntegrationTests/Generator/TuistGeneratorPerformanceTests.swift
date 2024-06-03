import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistLoaderTesting
import TuistSupport
import XcodeProj
import XCTest

@testable import TuistGenerator
@testable import TuistSupport
@testable import TuistSupportTesting

final class TuistGeneratorPerformanceTests: TuistTestCase {
    override func setUp() {
        super.setUp()
    }

    // MARK: - Tests

    func test_generateWorkspace_performance() throws {
        guard !isRunningInDebug() else {
            // Performance tests need to be run in Release Mode for more realistic results
            // Note: When we switch to Xcode11.5+ only on CI we can use `XCTSkipIf` instead of a guard statement
            //
            // XCTSkipIf(isRunningInDebug, "Performance tests need to be run in Release Mode for more realistic results")
            return
        }

        measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
            do {
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
                let temporaryPath = try self.temporaryPath()
                let modelGenerator = TestModelGenerator(rootPath: temporaryPath, config: config)
                let graph = try modelGenerator.generate()

                // When
                startMeasuring()
                let graphTraverser = GraphTraverser(graph: graph)
                _ = try subject.generateWorkspace(graphTraverser: graphTraverser)
                stopMeasuring()

            } catch {
                XCTFail("Failed to generate workspace: \(error)")
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
