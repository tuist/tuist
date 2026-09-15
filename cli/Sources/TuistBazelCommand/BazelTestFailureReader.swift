import Foundation
#if canImport(FoundationXML)
    import FoundationXML
#endif

struct BazelTestCaseIdentity: Hashable, Sendable {
    let target: String
    let suite: String
    let name: String
}

struct BazelTestFailureReader {
    func missingSkippedTargets(eventsURL: URL, skipped: Set<String>) -> Set<String> {
        do {
            let data = try Self.read(eventsURL, limit: 64 * 1024 * 1024)
            var missing = Set<String>()
            var finished = false
            var complete = false
            for line in data.split(separator: 0x0A) where !line.isEmpty {
                guard let event = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      let identifier = event["id"] as? [String: Any]
                else { return [] }
                // Aborted placeholders can have target identifiers without configuration or execution payloads.
                guard event["configured"] == nil, event["completed"] == nil,
                      event["action"] == nil, event["testResult"] == nil
                else { return [] }
                if let aborted = event["aborted"] as? [String: Any], let reason = aborted["reason"] as? String {
                    guard reason == "LOADING_FAILURE",
                          let patterns = (identifier["pattern"] as? [String: Any])?["pattern"] as? [String],
                          patterns.count == 1, let target = patterns.first, skipped.contains(target),
                          let description = aborted["description"] as? String,
                          description.hasPrefix("no such target '\(target)':") || description.hasPrefix("no such package '")
                    else { return [] }
                    missing.insert(target)
                }
                if let finish = event["finished"] as? [String: Any] {
                    finished = (finish["exitCode"] as? [String: Any])?["code"] as? Int == 1
                }
                complete = complete || event["lastMessage"] as? Bool == true
            }
            return finished && complete ? missing : []
        } catch {
            return []
        }
    }

    private struct Target: Hashable {
        let label: String
        let configuration: String

        init?(_ value: [String: Any]?) {
            guard let value, let label = value["label"] as? String else { return nil }
            self.label = label
            configuration = (value["configuration"] as? [String: Any])?["id"] as? String ?? ""
        }
    }

    func onlyMutedTestsFailed(
        eventsURL: URL,
        muted: Set<BazelTestCaseIdentity>,
        onLegacyMute: (BazelTestCaseIdentity, BazelTestCaseIdentity) -> Void = { _, _ in }
    ) -> Bool {
        do {
            let data = try Self.read(eventsURL, limit: 64 * 1024 * 1024)
            var expected = Set<Target>()
            var summaries: [Target: [String: Any]] = [:]
            var results: [Target: [[String: Any]]] = [:]
            var finished = false
            var complete = false

            for line in data.split(separator: 0x0A) where !line.isEmpty {
                guard let event = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      let identifier = event["id"] as? [String: Any]
                else { return false }
                for child in event["children"] as? [[String: Any]] ?? [] {
                    if let target = Target(child["testSummary"] as? [String: Any]) { expected.insert(target) }
                }
                if let target = Target(identifier["testSummary"] as? [String: Any]) {
                    guard let summary = event["testSummary"] as? [String: Any] else { return false }
                    summaries[target] = summary
                }
                if let target = Target(identifier["testResult"] as? [String: Any]) {
                    guard let result = event["testResult"] as? [String: Any] else { return false }
                    results[target, default: []].append(result)
                }
                if let finish = event["finished"] as? [String: Any] {
                    finished = (finish["exitCode"] as? [String: Any])?["code"] as? Int == 3
                }
                complete = complete || event["lastMessage"] as? Bool == true
            }

            guard finished, complete, !expected.isEmpty, expected == Set(summaries.keys) else { return false }
            var failedTargets = 0
            for (target, summary) in summaries {
                let status = summary["overallStatus"] as? String
                if status == "PASSED" || status == "FLAKY" { continue }
                guard status == "FAILED",
                      let count = summary["totalRunCount"] as? Int,
                      let attempts = results[target], count > 0, attempts.count == count
                else { return false }
                var failedAttempts = 0
                for attempt in attempts {
                    if attempt["status"] as? String == "PASSED" { continue }
                    guard attempt["status"] as? String == "FAILED",
                          let outputs = attempt["testActionOutput"] as? [[String: Any]],
                          let report = outputs.first(where: { $0["name"] as? String == "test.xml" }),
                          let uri = report["uri"] as? String, let url = URL(string: uri), url.isFileURL
                    else { return false }
                    let parsed = try Self.failureReport(in: Self.read(url, limit: 5 * 1024 * 1024), target: target.label)
                    for (current, legacy) in parsed.legacyIdentities where muted.contains(legacy) && !muted.contains(current) {
                        onLegacyMute(legacy, current)
                    }
                    guard !parsed.failures.isEmpty, parsed.failures.isSubset(of: muted) else { return false }
                    failedAttempts += 1
                }
                guard failedAttempts > 0 else { return false }
                failedTargets += 1
            }
            return failedTargets > 0
        } catch {
            return false
        }
    }

    static func failures(in data: Data, target: String) throws -> Set<BazelTestCaseIdentity> {
        try failureReport(in: data, target: target).failures
    }

    private static func failureReport(in data: Data, target: String) throws -> JunitFailureDelegate {
        guard let text = String(data: data, encoding: .utf8),
              text.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              text.range(of: "<!ENTITY", options: .caseInsensitive) == nil
        else { throw ReaderError.invalidReport }
        let delegate = JunitFailureDelegate(target: target)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), !delegate.invalid else { throw ReaderError.invalidReport }
        return delegate
    }

    private static func read(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw ReaderError.tooLarge }
        return data
    }

    private enum ReaderError: Error {
        case invalidReport
        case tooLarge
    }
}

private final class JunitFailureDelegate: NSObject, XMLParserDelegate {
    let target: String
    var failures = Set<BazelTestCaseIdentity>()
    var legacyIdentities: [BazelTestCaseIdentity: BazelTestCaseIdentity] = [:]
    var invalid = false
    private var elements: [String] = []
    private var suites: [String] = []
    private var testCase: BazelTestCaseIdentity?
    private var legacyTestCase: BazelTestCaseIdentity?

    init(target: String) { self.target = target }

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes: [String: String]
    ) {
        let element = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if element == "testsuite" { suites.append(field(attribute("name", in: attributes), fallback: "Unnamed suite")) }
        if element == "testcase" {
            guard elements.last == "testsuite", testCase == nil, let suite = suites.last else {
                invalid = true
                return
            }
            testCase = BazelTestCaseIdentity(
                target: target,
                suite: field(attribute("classname", in: attributes), fallback: suite),
                name: field(attribute("name", in: attributes), fallback: "Unnamed test")
            )
            legacyTestCase = BazelTestCaseIdentity(
                target: target,
                suite: suite,
                name: field(attribute("name", in: attributes), fallback: "Unnamed test")
            )
        }
        if element == "failure" || element == "error" {
            if elements.last == "testcase", let testCase {
                failures.insert(testCase)
                if let legacyTestCase, legacyTestCase != testCase {
                    legacyIdentities[testCase] = legacyTestCase
                }
            } else {
                invalid = true
            }
        }
        elements.append(element)
    }

    func parser(_: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
        let element = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if element == "testcase" {
            testCase = nil
            legacyTestCase = nil
        }
        if element == "testsuite", !suites.isEmpty { suites.removeLast() }
        if !elements.isEmpty { elements.removeLast() }
    }

    private func attribute(_ name: String, in attributes: [String: String]) -> String? {
        let matches = attributes.filter { $0.key.split(separator: ":").last.map(String.init) == name }
        guard matches.count <= 1 else {
            invalid = true
            return nil
        }
        return matches.first?.value
    }

    private func field(_ value: String?, fallback: String) -> String {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty { return fallback }
        // The server bounds report identities to the same number of UTF-8 bytes.
        var result = ""
        for character in value {
            guard result.utf8.count + String(character).utf8.count <= 1024 else { break }
            result.append(character)
        }
        return result.isEmpty ? fallback : result
    }
}
