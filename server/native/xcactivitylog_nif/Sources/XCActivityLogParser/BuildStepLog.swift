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
        for recorded in [[signature, command, output], messages].joined() where !recorded.isEmpty {
            // Bound normalization too: the recorded output can be much larger
            // than the log we retain, even after the build's budget is exhausted.
            let part = normalizedPrefix(recorded, limit: max(0, limit))
            if !part.truncated, result.contains(part.text) { continue }
            if !result.isEmpty, part.text.hasPrefix(result) { result = "" }
            let separator = result.isEmpty ? "" : "\n"
            let available = max(0, limit - result.utf8.count)
            let bytes = (separator + part.text).utf8
            if bytes.count > available {
                result += utf8Prefix(Array(bytes.prefix(available)))
                return (result, true)
            }
            result += separator + part.text
            if part.truncated { return (result, true) }
        }
        return (result, false)
    }

    private static func normalizedPrefix(_ text: String, limit: Int) -> (text: String, truncated: Bool) {
        var bytes: [UInt8] = []
        var previousWasCR = false
        for byte in text.utf8 {
            if previousWasCR, byte == 10 {
                previousWasCR = false
                continue
            }
            guard bytes.count < limit else { return (utf8Prefix(bytes), true) }
            previousWasCR = byte == 13
            bytes.append(previousWasCR ? 10 : byte)
        }
        return (String(decoding: bytes, as: UTF8.self), false)
    }

    private static func utf8Prefix(_ bytes: [UInt8]) -> String {
        var prefix = bytes
        while !prefix.isEmpty {
            if let text = String(bytes: prefix, encoding: .utf8) { return text }
            prefix.removeLast()
        }
        return ""
    }
}
