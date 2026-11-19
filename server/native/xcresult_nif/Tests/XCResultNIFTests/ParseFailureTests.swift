import Foundation
import Path
import Testing
import XCResultParser
@testable import XCResultNIF

struct ParseFailureTests {
    @Test(arguments: [
        (
            "Error: item missing for id 0~example==\nUsage: xcresulttool <subcommand>\nDetails: \"quoted\" \\路径\t⚠️",
            "missing_object"
        ),
        ("Error: unable to open result bundle", "command_failed"),
        ("Warning: Error: item missing for id 0~example==", "command_failed"),
    ])
    func failedTestResultsReturnStructuredDiagnostics(stderr: String, expectedCode: String) async throws {
        let parser = XCResultParser(execute: { _ in
            XCResultToolOutput(standardOutput: "", standardError: stderr, succeeded: false)
        })

        do {
            _ = try await parser.parse(path: AbsolutePath(validating: "/tmp/test.xcresult"), rootDirectory: nil)
            Issue.record("Expected parsing to fail")
        } catch {
            let data = try JSONEncoder().encode(ParseFailure(error))
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

            #expect(json["code"] as? String == expectedCode)
            #expect(json["command"] as? [String] == ["xcresulttool", "get", "test-results", "tests"])
            #expect(json["stderr"] as? String == stderr)
            #expect((json["error"] as? String)?.contains(stderr) == true)
        }
    }

    @Test
    func timeoutCodesComeFromErrorTypesRatherThanDescriptions() throws {
        let path = try AbsolutePath(validating: "/tmp/test.xcresult")
        let failures: [(any Error, String)] = [
            (XCResultParserError.timedOut(path, seconds: 600), "parse_timeout"),
            (XCResultParserError.failedToParseOutput(path), "parse_failed"),
            (
                NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "xcresult parsing timed out"]),
                "parse_failed"
            ),
        ]

        for (error, code) in failures {
            let data = try JSONEncoder().encode(ParseFailure(error))
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

            #expect(json["code"] as? String == code)
            #expect(json["error"] as? String == error.localizedDescription)
            #expect(json["command"] == nil)
            #expect(json["stderr"] == nil)
        }
    }

    @Test
    func nativeEntryPointPreservesToolDiagnosticsAsJSON() async throws {
        let missingPath = "/tmp/xcresult-nif-missing-\(UUID())/\"quoted\"/\\路径\nresult.xcresult"
        let expected = try await executeXCResultTool([
            "/usr/bin/xcrun", "xcresulttool", "get", "test-results", "tests", "--path", missingPath,
        ])
        #expect(!expected.succeeded)

        var output: UnsafeMutablePointer<CChar>?
        var length: Int32 = 0
        defer { output?.deallocate() }

        let status = missingPath.withCString { path in
            "/tmp".withCString { rootDir in
                parseXCResult(path, rootDir, &output, &length)
            }
        }

        #expect(status == 1)
        let buffer = try #require(output)
        let data = Data(bytes: buffer, count: Int(length))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["code"] as? String == "command_failed")
        #expect(json["command"] as? [String] == ["xcresulttool", "get", "test-results", "tests"])
        #expect(json["stderr"] as? String == expected.standardError)
        #expect((json["error"] as? String)?
            .contains(expected.standardError.trimmingCharacters(in: .whitespacesAndNewlines)) == true)
    }
}
