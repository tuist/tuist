import Foundation
import Path
import Testing
@testable import TuistXCResultService

struct CrashStackTraceTests {
    @Test
    func initializesWithAllFields() {
        let trace = CrashStackTrace(
            id: "550e8400-e29b-41d4-a716-446655440000",
            fileName: "MyApp-2024-01-15-123456.ips",
            appName: "MyApp",
            osVersion: "17.2",
            exceptionType: "EXC_CRASH",
            signal: "SIGABRT",
            exceptionSubtype: "KERN_INVALID_ADDRESS",
            filePath: try! AbsolutePath(validating: "/tmp/crash.ips")
        )

        #expect(trace.id == "550e8400-e29b-41d4-a716-446655440000")
        #expect(trace.fileName == "MyApp-2024-01-15-123456.ips")
        #expect(trace.appName == "MyApp")
        #expect(trace.osVersion == "17.2")
        #expect(trace.exceptionType == "EXC_CRASH")
        #expect(trace.signal == "SIGABRT")
        #expect(trace.exceptionSubtype == "KERN_INVALID_ADDRESS")
        let expectedPath = try! AbsolutePath(validating: "/tmp/crash.ips")
        #expect(trace.filePath == expectedPath)
    }

    @Test
    func initializesWithNilOptionalFields() {
        let trace = CrashStackTrace(
            id: "test-id",
            fileName: "crash.ips",
            appName: nil,
            osVersion: nil,
            exceptionType: nil,
            signal: nil,
            exceptionSubtype: nil,
            filePath: try! AbsolutePath(validating: "/tmp/crash.ips")
        )

        #expect(trace.appName == nil)
        #expect(trace.osVersion == nil)
        #expect(trace.exceptionType == nil)
        #expect(trace.signal == nil)
        #expect(trace.exceptionSubtype == nil)
    }
}

struct TestCaseStackTraceTests {
    @Test
    func testCaseHasNilStackTraceIdByDefault() {
        let testCase = TestCase(
            name: "testExample",
            testSuite: "MySuite",
            module: "MyModule",
            duration: 100,
            status: .passed,
            failures: []
        )

        #expect(testCase.stackTraceId == nil)
    }

    @Test
    func testCaseCanHaveStackTraceId() {
        let testCase = TestCase(
            name: "testCrash",
            testSuite: "MySuite",
            module: "MyModule",
            duration: 50,
            status: .failed,
            failures: [],
            stackTraceId: "some-uuid"
        )

        #expect(testCase.stackTraceId == "some-uuid")
    }
}

struct TestSummaryStackTraceTests {
    @Test
    func testSummaryHasEmptyStackTracesByDefault() {
        let summary = TestSummary(
            testPlanName: "MyPlan",
            status: .passed,
            duration: 1000,
            testModules: []
        )

        #expect(summary.stackTraces.isEmpty)
    }

    @Test
    func testSummaryCanHaveStackTraces() {
        let trace = CrashStackTrace(
            id: "trace-id",
            fileName: "crash.ips",
            appName: nil,
            osVersion: nil,
            exceptionType: nil,
            signal: nil,
            exceptionSubtype: nil,
            filePath: try! AbsolutePath(validating: "/tmp/crash.ips")
        )

        let summary = TestSummary(
            testPlanName: "MyPlan",
            status: .failed,
            duration: 500,
            testModules: [],
            stackTraces: [trace]
        )

        #expect(summary.stackTraces.count == 1)
        #expect(summary.stackTraces[0].id == "trace-id")
    }
}
