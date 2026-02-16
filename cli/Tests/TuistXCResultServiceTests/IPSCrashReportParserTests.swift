import Foundation
import Testing
@testable import TuistXCResultService

struct IPSCrashReportParserTests {
    let parser = IPSCrashReportParser()

    private func fixtureContent() throws -> String {
        let fixturePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("crash-report.ips")
        return try String(contentsOf: fixturePath, encoding: .utf8)
    }

    @Test
    func parse_returnsExceptionMetadata() throws {
        let result = try parser.parse(try fixtureContent())

        #expect(result.exceptionType == "EXC_BREAKPOINT")
        #expect(result.signal == "SIGTRAP")
    }

    @Test
    func parse_returnsTriggeredThreadFrames() throws {
        let result = try parser.parse(try fixtureContent())

        let frames = try #require(result.triggeredThreadFrames)
        let lines = frames.components(separatedBy: "\n")
        #expect(lines[0].contains("libswiftCore.dylib"))
        #expect(lines[0].contains("_assertionFailure"))
        #expect(lines[1].contains("AppTests"))
        #expect(lines[1].contains("AppTests.example()"))
        #expect(lines[1].contains("AppTests.swift:7"))
    }

    @Test
    func parse_withInvalidContent_throws() {
        #expect(throws: IPSCrashReportParserError.self) {
            try parser.parse("not valid")
        }
    }

    @Test
    func parse_withEmptyContent_throws() {
        #expect(throws: IPSCrashReportParserError.self) {
            try parser.parse("")
        }
    }
}
