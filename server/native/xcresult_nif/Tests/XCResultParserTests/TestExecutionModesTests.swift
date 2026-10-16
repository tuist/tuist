import Foundation
import Testing
@testable import XCResultParser

struct TestExecutionModesTests {
    @Test
    func roundTripsThroughTheBundle() throws {
        let bundle = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle) }

        #expect(TestExecutionModes.read(fromResultBundle: bundle) == nil)

        let modes = TestExecutionModes(run: "parallel", targets: ["AppTests": "parallel", "CoreTests": "serial"])
        try modes.write(toResultBundle: bundle)

        #expect(TestExecutionModes.read(fromResultBundle: bundle) == modes)
    }

    @Test
    func appliesTheRunAndTargetModesToASummary() {
        let summary = TestSummary(
            testPlanName: "App",
            status: .passed,
            duration: 10,
            testModules: [
                TestModule(name: "AppTests", status: .passed, duration: 5, testSuites: [], testCases: []),
                TestModule(name: "CoreTests", status: .passed, duration: 5, testSuites: [], testCases: []),
                TestModule(name: "UnknownTests", status: .passed, duration: 5, testSuites: [], testCases: []),
            ]
        )

        let applied = summary.applying(
            executionModes: TestExecutionModes(run: "parallel", targets: ["AppTests": "parallel", "CoreTests": "serial"])
        )

        #expect(applied.executionMode == "parallel")
        #expect(applied.testModules.map(\.executionMode) == ["parallel", "serial", "parallel"])
        #expect(summary.applying(executionModes: nil).executionMode == nil)
    }

    @Test
    func encodesTheModesWithTheSummary() throws {
        var summary = TestSummary(
            testPlanName: "App",
            status: .passed,
            duration: 10,
            testModules: [TestModule(
                name: "AppTests",
                status: .passed,
                duration: 5,
                testSuites: [],
                testCases: [],
                executionMode: "serial"
            )]
        )
        summary.executionMode = "serial"

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(summary)) as? [String: Any]
        #expect(json?["execution_mode"] as? String == "serial")
        #expect(((json?["test_modules"] as? [[String: Any]])?.first?["execution_mode"]) as? String == "serial")
    }
}
