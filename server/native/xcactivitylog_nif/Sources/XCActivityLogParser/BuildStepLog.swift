import Foundation
import XCLogParser

struct BuildStepLog {
    struct Key: Hashable {
        let signature: String
        let start: Double
        let end: Double
    }

    private var sections: [Key: [IDEActivityLogSection]] = [:]

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

    /// `steps` is the emitted step followed by any sub-steps folded into it.
    func extract(steps: [BuildStep]) -> (text: String, truncated: Bool) {
        // Synthetic or ambiguous parser steps still have a signature, but must
        // never inherit another operation's command or output.
        let sections = steps.compactMap { step -> IDEActivityLogSection? in
            let matches = self.sections[Key(signature: step.signature, start: step.startTimestamp, end: step.endTimestamp)] ?? []
            return matches.count == 1 ? matches[0] : nil
        }
        return Self.render(
            signature: steps.first?.signature ?? "",
            command: sections.map(\.commandDetailDesc).filter { !$0.isEmpty }.joined(separator: "\n"),
            output: sections.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n"),
            messages: sections.flatMap { $0.messages.map(\.title) },
            limit: 64 * 1024
        )
    }

    static func render(signature: String, command: String, output: String, messages: [String], limit: Int) -> (text: String, truncated: Bool) {
        let result = renderPrefix(signature: signature, command: command, output: output, messages: messages, limit: limit)
        let marker = "\n… log truncated …\n"
        guard result.truncated, limit >= marker.utf8.count + 8 else { return result }
        let tailLimit = (limit - marker.utf8.count) / 2
        let tail = normalizedSuffix(parts: [[signature, command, output], messages].joined(), limit: tailLimit)
        let head = utf8Prefix(Array(result.text.utf8.prefix(limit - marker.utf8.count - tail.utf8.count)))
        return (head + marker + tail, true)
    }

    private static func renderPrefix(signature: String, command: String, output: String, messages: [String], limit: Int) -> (text: String, truncated: Bool) {
        var result = ""
        for recorded in [[signature, command, output], messages].joined() where !recorded.isEmpty {
            // Bound normalization too: the recorded output can be much larger
            // than the log we retain.
            let part = normalizedPrefix(recorded, limit: max(0, limit))
            if !part.truncated, containsBytes(result, part.text) { continue }
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

    // Foundation's Unicode-aware `contains` dominated parsing for Swift jobs
    // with hundreds of messages. Both sides are normalized, so bytes suffice.
    private static func containsBytes(_ haystack: String, _ needle: String) -> Bool {
        var haystack = haystack
        var needle = needle
        return haystack.withUTF8 { h in
            needle.withUTF8 { n in
                guard let first = n.first, let hBase = h.baseAddress, let nBase = n.baseAddress else { return n.isEmpty }
                guard n.count <= h.count else { return false }
                for i in 0 ... (h.count - n.count) where h[i] == first {
                    if memcmp(hBase + i, nBase, n.count) == 0 { return true }
                }
                return false
            }
        }
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

    private static func normalizedSuffix(parts: some BidirectionalCollection<String>, limit: Int) -> String {
        var bytes: [UInt8] = []
        for recorded in parts.reversed() where !recorded.isEmpty {
            if !bytes.isEmpty {
                if bytes.count == limit { break }
                bytes.append(UInt8(10))
            }
            var part = recorded
            part.withUTF8 { buffer in
                var previousWasLF = false
                for byte in buffer.reversed() {
                    if previousWasLF, byte == 13 {
                        previousWasLF = false
                        continue
                    }
                    if bytes.count == limit { break }
                    previousWasLF = byte == 10
                    bytes.append(byte == 13 ? 10 : byte)
                }
            }
            if bytes.count == limit { break }
        }
        var suffix = Array(bytes.reversed())
        while !suffix.isEmpty {
            if let text = String(bytes: suffix, encoding: .utf8) { return text }
            suffix.removeFirst()
        }
        return ""
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
