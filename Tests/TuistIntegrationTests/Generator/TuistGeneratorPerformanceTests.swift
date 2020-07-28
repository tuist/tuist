import TSCBasic
import TuistCore
import TuistCoreTesting
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
        measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
            do {
                // Given
                let subject = DescriptorGenerator()
                let config = TestModelGenerator.WorkspaceConfig(projects: 50,
                                                                testTargets: 5,
                                                                frameworkTargets: 5,
                                                                schemes: 10,
                                                                sources: 200,
                                                                resources: 100,
                                                                headers: 100)
                let temporaryPath = try self.temporaryPath()
                let modelGenerator = TestModelGenerator(rootPath: temporaryPath, config: config)
                let (graph, workspace) = try modelGenerator.generate()

                // When
                startMeasuring()
                _ = try subject.generateWorkspace(workspace: workspace, graph: graph)
                stopMeasuring()

            } catch {
                XCTFail("Failed to generate workspace: \(error)")
            }
        }
    }
}
