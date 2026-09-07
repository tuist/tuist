import FileSystem
import FileSystemTesting
import Foundation
import Testing

@testable import TuistBazelCommand

struct BazelTestFailureReaderTests {
    @Test func distinguishes_equal_case_names_in_different_classes() throws {
        let report = """
        <testsuite name="All tests">
          <testcase classname="MutedClass" name="test"><failure/></testcase>
          <testcase classname="HealthyClass" name="test"><failure/></testcase>
        </testsuite>
        """
        #expect(try BazelTestFailureReader.failures(in: Data(report.utf8), target: "//app:tests") == [
            BazelTestCaseIdentity(target: "//app:tests", suite: "MutedClass", name: "test"),
            BazelTestCaseIdentity(target: "//app:tests", suite: "HealthyClass", name: "test"),
        ])
    }

    @Test func matches_failures_by_target_suite_and_case() throws {
        let report = """
        <testsuites><testsuite name="Suite"><testcase name="muted"><failure>failure</failure></testcase>
        <testcase name="healthy"/></testsuite></testsuites>
        """
        #expect(try BazelTestFailureReader.failures(in: Data(report.utf8), target: "//app:tests") == [
            BazelTestCaseIdentity(target: "//app:tests", suite: "Suite", name: "muted"),
        ])
    }

    @Test(arguments: [
        "<!DOCTYPE testsuite [<!ENTITY secret SYSTEM 'file:///etc/passwd'>]><testsuite/>",
        "<testsuite><error>runner crashed</error></testsuite>",
        "<testsuite><testcase><failure>",
    ])
    func rejects_unsafe_incomplete_or_unattributed_reports(report: String) {
        #expect(throws: (any Error).self) {
            try BazelTestFailureReader.failures(in: Data(report.utf8), target: "//app:tests")
        }
    }

    @Test(.inTemporaryDirectory, arguments: [true, false])
    func only_suppresses_fully_observed_muted_failures(includeHealthyFailure: Bool) async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let report = directory.appending(component: "test.xml")
        let events = directory.appending(component: "events.json")
        let extra = includeHealthyFailure ? "<testcase name=\"healthy\"><failure/></testcase>" : ""
        try await FileSystem().writeText(
            "<testsuite name=\"Suite\"><testcase name=\"muted\"><failure/></testcase>\(extra)</testsuite>", at: report
        )
        let reportURL = URL(fileURLWithPath: report.pathString).absoluteString
        let identifier: [String: Any] = ["label": "//app:tests", "configuration": ["id": "config"]]
        let rows: [[String: Any]] = [
            ["id": ["targetCompleted": identifier], "children": [["testSummary": identifier]]],
            ["id": ["testResult": identifier], "testResult": [
                "status": "FAILED", "testActionOutput": [["name": "test.xml", "uri": reportURL]],
            ]],
            ["id": ["testSummary": identifier], "testSummary": ["overallStatus": "FAILED", "totalRunCount": 1]],
            ["id": ["buildFinished": [:]], "finished": ["exitCode": ["code": 3]], "lastMessage": true],
        ]
        let contents = try rows.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
            .joined(separator: "\n")
        try await FileSystem().writeText(contents, at: events)
        let muted: Set<BazelTestCaseIdentity> = [.init(target: "//app:tests", suite: "Suite", name: "muted")]
        #expect(BazelTestFailureReader().onlyMutedTestsFailed(
            eventsURL: URL(fileURLWithPath: events.pathString), muted: muted
        ) == !includeHealthyFailure)
        try await FileSystem().writeText(
            contents.components(separatedBy: "\n").dropLast().joined(separator: "\n"),
            at: events,
            options: [.overwrite]
        )
        #expect(!BazelTestFailureReader().onlyMutedTestsFailed(eventsURL: URL(fileURLWithPath: events.pathString), muted: muted))
    }
}
