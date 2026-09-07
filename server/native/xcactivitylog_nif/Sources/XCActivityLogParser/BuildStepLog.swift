import Foundation
import XCLogParser

struct BuildStepLog {
    struct Key: Hashable {
        let signature: String
        let start: Double
        let end: Double
    }

    private var sections: [Key: [IDEActivityLogSection]] = [:]
    private var remainingBytes = 16 * 1024 * 1024

    init(root: IDEActivityLogSection) {
        var pending = [root]
        while let section = pending.popLast() {
            let key = Key(
                signature: section.signature,
                start: section.timeStartedRecording + Date.timeIntervalBetween1970AndReferenceDate,
                end: section.timeStoppedRecording + Date.timeIntervalBetween1970AndReferenceDate
            )
            sections[key, default: []].append(section)
            pending.append(contentsOf: section.subSections)
        }
    }

    mutating func extract(step: BuildStep) -> (text: String, truncated: Bool) {
        let key = Key(signature: step.signature, start: step.startTimestamp, end: step.endTimestamp)
        let matches = sections[key] ?? []
        // Synthetic or ambiguous parser steps still have a signature, but must
        // never inherit another operation's command or output.
        let section = matches.count == 1 ? matches[0] : nil
        let result = Self.render(
            signature: step.signature,
            command: section?.commandDetailDesc ?? "",
            output: section?.text ?? "",
            messages: section?.messages.map(\.title) ?? [],
            limit: min(64 * 1024, remainingBytes)
        )
        remainingBytes -= result.text.utf8.count
        return result
    }

    static func render(signature: String, command: String, output: String, messages: [String], limit: Int) -> (text: String, truncated: Bool) {
        var result = ""
        for recorded in [signature, command, output] + messages where !recorded.isEmpty {
            let part = recorded.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            if result.contains(part) { continue }
            if !result.isEmpty, part.hasPrefix(result) { result = "" }
            let separator = result.isEmpty ? "" : "\n"
            let available = max(0, limit - result.utf8.count)
            let bytes = (separator + part).utf8
            if bytes.count > available {
                var prefix = Array(bytes.prefix(available))
                while !prefix.isEmpty, String(bytes: prefix, encoding: .utf8) == nil { prefix.removeLast() }
                result += String(bytes: prefix, encoding: .utf8) ?? ""
                return (result, true)
            }
            result += separator + part
        }
        return (result, false)
    }
}
