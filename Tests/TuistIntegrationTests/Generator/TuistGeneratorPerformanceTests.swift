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
    private let manualTimer = ManualTestTimer()

    override func setUpWithError() throws {
        try XCTSkipIf(
            isRunningInDebug(),
            "Performance tests need to be run in Release Mode for more realistic results"
        )
    }

    // MARK: - Tests

    func test_generateWorkspace_performance() throws {
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
        measure {
            do {
                _ = try subject.generateWorkspace(workspace: workspace, graph: graph)
            } catch {
                XCTFail("Failed to generate workspace: \(error)")
            }
        }

        // Currently Swift PM doesn't support setting baselines, as such we'll need to
        // manually assert measurements are within an expected value and tolerance
        try assertMeasurement(tolerancePercentage: 0.1)
    }

    // MARK: - Overrides

    override func startMeasuring() {
        super.startMeasuring()
        manualTimer.start()
    }

    override func stopMeasuring() {
        super.stopMeasuring()
        manualTimer.stop()
    }

    // MARK: - Helpers

    private func isRunningInDebug() -> Bool {
        #if DEBUG
            return true
        #else
            return false
        #endif
    }

    private func assertMeasurement(tolerancePercentage: Double,
                                   file: StaticString = #file,
                                   line: UInt = #line) throws
    {
        if shouldRecordBaselines() {
            try save(baseline: Baseline(measurements: manualTimer.measurements))
        } else {
            guard let baseline = try loadBaseline() else {
                if shouldFailForMissingBaselines() {
                    XCTFail("Baseline measurements were not found.")
                } else {
                    print("Skipping assertion, baseline measurements were not found.")
                }
                return
            }
            let expectedDuration = baseline.measurements.average()
            let average = manualTimer.measurements.average()
            let accuracy = expectedDuration * tolerancePercentage
            let percentageString = String(format: "%.2f", tolerancePercentage * 100)
            XCTAssertEqual(average,
                           expectedDuration,
                           accuracy: accuracy,
                           "The measurement \(average) wasn't within expected range ~(\(expectedDuration) ±\(percentageString)%)",
                           file: file,
                           line: line)
        }
    }

    private func shouldRecordBaselines() -> Bool {
        ProcessInfo.processInfo.environment["TEST_RECORD_BASELINES"] == "1"
    }

    private func shouldFailForMissingBaselines() -> Bool {
        ProcessInfo.processInfo.environment["TEST_FAIL_MISSING_BASELINES"] == "1"
    }

    private func currentTestBaselineFilePath() -> AbsolutePath {
        let currentTestIdentifier = name
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: " ", with: ".")
        return AbsolutePath(#file)
            .parentDirectory
            .parentDirectory
            .parentDirectory
            .parentDirectory
            .appending(component: "performance_tests_baselines")
            .appending(component: currentTestIdentifier)
    }

    private func loadBaseline() throws -> Baseline? {
        let fileHandler = FileHandler()
        let baselineFile = currentTestBaselineFilePath()
        guard fileHandler.exists(baselineFile) else {
            return nil
        }
        let data = try fileHandler.readFile(baselineFile)
        return try JSONDecoder().decode(Baseline.self, from: data)
    }

    private func save(baseline: Baseline) throws {
        let fileHandler = FileHandler()
        let baselineFile = currentTestBaselineFilePath()
        if fileHandler.exists(baselineFile) {
            try fileHandler.delete(baselineFile)
        }
        try fileHandler.createFolder(baselineFile.parentDirectory)
        let data = try JSONEncoder().encode(baseline)
        try data.write(to: baselineFile.asURL)
    }

    // MARK: - Helper Classes

    struct Baseline: Codable {
        var measurements: [TimeInterval]
    }

    private final class ManualTestTimer {
        private let clock = WallClock()
        private(set) var measurements: [TimeInterval] = []
        private var currentTimer: ClockTimer?

        func start() {
            currentTimer = clock.startTimer()
        }

        func stop() {
            guard let elapsedTime = currentTimer?.stop() else {
                return
            }
            measurements.append(elapsedTime)
            currentTimer = nil
        }
    }
}

private extension Array where Element == Double {
    func average() -> Double {
        reduce(0, +) / Double(count)
    }
}
