import Foundation
import Path
import Testing
@testable import TuistXCResultService

struct CrashReportTests {
    @Test
    func initializesWithAllFields() throws {
        let filePath = try AbsolutePath(validating: "/tmp/crash.ips")
        let trace = CrashReport(
            exceptionType: "EXC_CRASH",
            signal: "SIGABRT",
            exceptionSubtype: "KERN_INVALID_ADDRESS",
            filePath: filePath,
            triggeredThreadFrames: "0  libswiftCore.dylib  _assertionFailure + 156"
        )

        #expect(trace.exceptionType == "EXC_CRASH")
        #expect(trace.signal == "SIGABRT")
        #expect(trace.exceptionSubtype == "KERN_INVALID_ADDRESS")
        #expect(trace.filePath == filePath)
        #expect(trace.triggeredThreadFrames == "0  libswiftCore.dylib  _assertionFailure + 156")
    }

    @Test
    func initializesWithNilOptionalFields() throws {
        let trace = CrashReport(
            exceptionType: nil,
            signal: nil,
            exceptionSubtype: nil,
            filePath: try AbsolutePath(validating: "/tmp/crash.ips")
        )

        #expect(trace.exceptionType == nil)
        #expect(trace.signal == nil)
        #expect(trace.exceptionSubtype == nil)
        #expect(trace.triggeredThreadFrames == nil)
    }
}

struct TestCaseCrashReportTests {
    @Test
    func testCaseHasNilCrashReportByDefault() {
        let testCase = TestCase(
            name: "testExample",
            testSuite: "MySuite",
            module: "MyModule",
            duration: 100,
            status: .passed,
            failures: []
        )

        #expect(testCase.crashReport == nil)
    }

    @Test
    func testCaseCanHaveCrashReport() throws {
        let trace = CrashReport(
            exceptionType: "EXC_CRASH",
            signal: nil,
            exceptionSubtype: nil,
            filePath: try AbsolutePath(validating: "/tmp/crash.ips")
        )

        let testCase = TestCase(
            name: "testCrash",
            testSuite: "MySuite",
            module: "MyModule",
            duration: 50,
            status: .failed,
            failures: [],
            crashReport: trace
        )

        #expect(testCase.crashReport?.exceptionType == "EXC_CRASH")
    }
}
