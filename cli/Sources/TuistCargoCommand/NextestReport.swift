import Foundation
import TuistServer
#if canImport(FoundationXML)
    import FoundationXML
#endif

struct NextestInventory: Decodable {
    struct Suite: Decodable {
        struct Test: Decodable {
            let ignored: Bool
            let filterMatch: Match?
            struct Match: Decodable { let status: String }
            enum CodingKeys: String, CodingKey { case ignored; case filterMatch = "filter-match" }
        }

        let binaryID: String
        let testcases: [String: Test]
        enum CodingKeys: String, CodingKey { case binaryID = "binary-id"; case testcases }
    }

    struct BuildMetadata: Decodable {
        let targetDirectory: String
        enum CodingKeys: String, CodingKey { case targetDirectory = "target-directory" }
    }

    let suites: [String: Suite]
    let buildMetadata: BuildMetadata?
    enum CodingKeys: String, CodingKey { case suites = "rust-suites"; case buildMetadata = "rust-build-meta" }

    var modules: [String] {
        suites.values.filter { $0.testcases.values.contains { !$0.ignored && $0.filterMatch?.status == "matches" } }
            .map(\.binaryID).sorted()
    }

    var enumeration: [[String: Any]] {
        suites.values.flatMap { suite in
            suite.testcases.map { name, test in
                let identity = NextestReport.identity(name)
                return ["module": suite.binaryID, "suite": identity.suite, "name": identity.name, "enabled": !test.ignored]
            }
        }
    }
}

final class NextestReport: NSObject, XMLParserDelegate {
    struct Attempt {
        var duration: Int
        var status: String
        var message: String
        var startedAt: Date?
    }

    struct Test {
        var module: String
        var fullName: String
        var duration: Int
        var startedAt: Date?
        var status = "success"
        var message = ""
        var retries: [Attempt] = []
    }

    private(set) var tests: [Test] = []
    private(set) var duration = 0
    private var module = ""
    private var current: Test?
    private var text = ""
    private var failureElement: String?
    private var retryDuration = 0
    private var retryStartedAt: Date?
    private var rejected = false
    private var foundRoot = false

    static func read(_ url: URL) throws -> NextestReport {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 50_000_000 else { throw CargoReportError(message: "Nextest report exceeds 50 MB.") }
        let data = try Data(contentsOf: url)
        guard let xml = String(data: data, encoding: .utf8), !xml.contains("<!DOCTYPE") else {
            throw CargoReportError(message: "Nextest report contains a document type declaration.")
        }
        let report = NextestReport()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = report
        guard parser.parse(), !report.rejected, report.foundRoot else {
            throw CargoReportError(message: "Nextest produced an invalid test report.")
        }
        return report
    }

    static func identity(_ fullName: String) -> (suite: String, name: String) {
        let parts = fullName.components(separatedBy: "::")
        return (parts.dropLast().joined(separator: "::"), parts.last ?? fullName)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes: [String: String]
    ) {
        switch elementName {
        case "testsuites":
            foundRoot = true
            duration = Self.milliseconds(attributes["time"])
        case "testsuite": module = attributes["name"] ?? ""
        case "testcase":
            guard tests.count < 500_000, let name = attributes["name"], name.utf8.count <= 4096,
                  !module.isEmpty, module.utf8.count <= 4096
            else {
                rejected = true
                parser.abortParsing()
                return
            }
            current = Test(
                module: module,
                fullName: name,
                duration: Self.milliseconds(attributes["time"]),
                startedAt: Self.timestamp(attributes["timestamp"])
            )
        case "skipped": current?.status = "skipped"
        case "failure", "error", "flakyFailure", "flakyError", "rerunFailure", "rerunError":
            failureElement = elementName
            text = attributes["message"] ?? ""
            retryDuration = Self.milliseconds(attributes["time"])
            retryStartedAt = Self.timestamp(attributes["timestamp"])
        default: break
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        if failureElement != nil, text.utf8.count < 10000 { text += String(string.prefix(10000)) }
    }

    func parser(_: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
        if elementName == failureElement {
            if elementName == "failure" || elementName == "error" {
                current?.status = "failure"
                current?.message = String(text.prefix(10000))
            } else {
                current?.retries.append(Attempt(
                    duration: retryDuration, status: "failure", message: String(text.prefix(10000)), startedAt: retryStartedAt
                ))
            }
            failureElement = nil
        }
        if elementName == "testcase", let current {
            tests.append(current)
            self.current = nil
        }
    }

    private static func milliseconds(_ value: String?) -> Int {
        guard let seconds = Double(value ?? "0"), seconds.isFinite, seconds >= 0 else { return 0 }
        return Int(min((seconds * 1000).rounded(), Double(Int32.max)))
    }

    private static func timestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: value) { return date }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: value)
    }

    private func timingWindow(_ tests: [Test]) -> (start: Date, end: Date)? {
        let attempts = tests.filter { $0.status != "skipped" }.flatMap { test in
            [Attempt(duration: test.duration, status: test.status, message: test.message, startedAt: test.startedAt)] + test
                .retries
        }
        let windows = attempts.compactMap { attempt -> (start: Date, end: Date)? in
            guard let start = attempt.startedAt else { return nil }
            return (start, start.addingTimeInterval(Double(attempt.duration) / 1000))
        }
        guard windows.count == attempts.count, let start = windows.map(\.start).min(), let end = windows.map(\.end).max()
        else { return nil }
        return (start, end)
    }

    private func elapsed(_ tests: [Test]) -> Int {
        if let window = timingWindow(tests) {
            let elapsed = CargoCommandService.milliseconds(window.end.timeIntervalSince(window.start))
            return duration > 0 ? min(duration, elapsed) : elapsed
        }
        let sum = tests.filter { $0.status != "skipped" }
            .reduce(0) { $0 + $1.duration + $1.retries.reduce(0) { $0 + $1.duration } }
        return min(Int(Int32.max), duration > 0 ? min(duration, sum) : sum)
    }

    var modules: [[String: Any]] {
        Dictionary(grouping: tests, by: \.module).sorted { $0.key < $1.key }.map { module, tests in
            let cases: [[String: Any]] = tests.map { test in
                let identity = Self.identity(test.fullName)
                var payload: [String: Any] = [
                    "name": identity.name, "test_suite_name": identity.suite,
                    "duration": min(Int(Int32.max), test.duration + test.retries.reduce(0) { $0 + $1.duration }),
                    "status": test.status,
                ]
                if !test.message.isEmpty {
                    payload["failures"] = [["message": test.message, "issue_type": "assertion_failure", "line_number": 0]]
                }
                if !test.retries.isEmpty {
                    let primary = Attempt(duration: test.duration, status: test.status, message: test.message)
                    let attempts = test.status == "failure" ? [primary] + test.retries : test.retries + [primary]
                    payload["repetitions"] = attempts.enumerated().map { index, attempt in
                        [
                            "name": "Attempt \(index + 1)",
                            "repetition_number": index + 1,
                            "duration": attempt.duration,
                            "status": attempt.status,
                            "source": "run",
                        ] as [String: Any]
                    }
                }
                return payload
            }
            let suites: [[String: Any]] = Dictionary(grouping: tests, by: { Self.identity($0.fullName).suite })
                .sorted { $0.key < $1.key }.map { name, cases in
                    [
                        "name": name,
                        "duration": elapsed(cases),
                        "status": cases.contains { $0.status == "failure" } ? "failure" : "success",
                    ]
                }
            var payload: [String: Any] = [
                "name": module,
                "duration": elapsed(tests),
                "status": tests.contains { $0.status == "failure" } ? "failure" : "success",
                "test_cases": cases,
                "test_suites": suites,
            ]
            if duration > 0, timingWindow(tests) != nil { payload["execution_mode"] = "parallel" }
            return payload
        }
    }
}
