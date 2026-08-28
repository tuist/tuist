import Foundation

struct BazelCriticalPathActionTelemetry: Sendable, Equatable {
    let description: String
    let durationMilliseconds: Int
}

struct BazelCriticalPathTelemetry: Sendable, Equatable {
    let durationMilliseconds: Int
    let actions: [BazelCriticalPathActionTelemetry]
}

struct BazelBuildTimelineSpanTelemetry: Sendable, Equatable {
    let lane: Int
    let startMilliseconds: Int
    let durationMilliseconds: Int
    let category: String
    let description: String
}

struct BazelBuildTimelineTelemetry: Sendable, Equatable {
    let durationMilliseconds: Int
    let laneLabels: [String]
    let spans: [BazelBuildTimelineSpanTelemetry]
}

struct BazelProfileTelemetry: Sendable, Equatable {
    let criticalPath: BazelCriticalPathTelemetry?
    let buildTimeline: BazelBuildTimelineTelemetry?
}

struct BazelProfileParser {
    private static let maximumActionCount = 25
    private static let maximumActionDescriptionLength = 512
    private static let maximumTimelineLaneCount = 8
    private static let maximumTimelineSpanCount = 180
    private static let minimumTimelineSpanDurationMicroseconds = 5000

    func parse(data: Data) -> BazelCriticalPathTelemetry? {
        parseTelemetry(data: data)?.criticalPath
    }

    func parseTelemetry(data: Data) -> BazelProfileTelemetry? {
        guard let profile = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = profile["traceEvents"] as? [[String: Any]]
        else {
            return nil
        }

        return BazelProfileTelemetry(
            criticalPath: criticalPath(in: events),
            buildTimeline: buildTimeline(in: events)
        )
    }

    private func criticalPath(in events: [[String: Any]]) -> BazelCriticalPathTelemetry? {
        guard let criticalPathThreadIdentifier = criticalPathThreadIdentifier(in: events) else {
            return nil
        }

        let allActions = events
            .filter { event in
                integer(event["tid"]) == criticalPathThreadIdentifier &&
                    string(event["ph"]) == "X" &&
                    string(event["cat"]) == "critical path component"
            }
            .compactMap(action(from:))
            .sorted { $0.timestamp < $1.timestamp }

        guard !allActions.isEmpty else { return nil }

        return BazelCriticalPathTelemetry(
            durationMilliseconds: allActions.reduce(0) { $0 + $1.action.durationMilliseconds },
            actions: Array(allActions.prefix(Self.maximumActionCount).map(\.action))
        )
    }

    private func buildTimeline(in events: [[String: Any]]) -> BazelBuildTimelineTelemetry? {
        let criticalPathThreadIdentifier = criticalPathThreadIdentifier(in: events)
        let candidates = events.compactMap(timelineCandidate(from:))

        guard !candidates.isEmpty else { return nil }

        let selectedThreadIdentifiers =
            candidates
                .reduce(into: [Int: Int]()) { totals, candidate in
                    totals[candidate.threadIdentifier, default: 0] += candidate.durationMicroseconds
                }
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value {
                        return lhs.key < rhs.key
                    }

                    return lhs.value > rhs.value
                }
                .map(\.key)
                .prefix(Self.maximumTimelineLaneCount)

        var threadIdentifiers = Array(selectedThreadIdentifiers)

        if let criticalPathThreadIdentifier,
           candidates.contains(where: { $0.threadIdentifier == criticalPathThreadIdentifier }),
           !threadIdentifiers.contains(criticalPathThreadIdentifier)
        {
            threadIdentifiers = Array(threadIdentifiers.dropLast())
            threadIdentifiers.insert(criticalPathThreadIdentifier, at: 0)
        } else if let criticalPathThreadIdentifier,
                  let criticalPathIndex = threadIdentifiers.firstIndex(of: criticalPathThreadIdentifier)
        {
            threadIdentifiers.remove(at: criticalPathIndex)
            threadIdentifiers.insert(criticalPathThreadIdentifier, at: 0)
        }

        let laneByThreadIdentifier = Dictionary(uniqueKeysWithValues: threadIdentifiers.enumerated().map { ($1, $0) })
        let firstTimestamp = candidates.map(\.timestampMicroseconds).min() ?? 0
        var workerNumber = 0
        let laneLabels = threadIdentifiers.map { threadIdentifier in
            if threadIdentifier == criticalPathThreadIdentifier {
                return "Critical path"
            }

            workerNumber += 1
            return "Worker \(workerNumber)"
        }

        let spans =
            candidates
                .filter { laneByThreadIdentifier[$0.threadIdentifier] != nil }
                .sorted { lhs, rhs in
                    if lhs.durationMicroseconds == rhs.durationMicroseconds {
                        return lhs.timestampMicroseconds < rhs.timestampMicroseconds
                    }

                    return lhs.durationMicroseconds > rhs.durationMicroseconds
                }
                .prefix(Self.maximumTimelineSpanCount)
                .compactMap { candidate -> BazelBuildTimelineSpanTelemetry? in
                    guard let lane = laneByThreadIdentifier[candidate.threadIdentifier] else { return nil }

                    return BazelBuildTimelineSpanTelemetry(
                        lane: lane,
                        startMilliseconds: max(Int(((candidate.timestampMicroseconds - firstTimestamp) / 1000).rounded()), 0),
                        durationMilliseconds: max(Int((Double(candidate.durationMicroseconds) / 1000).rounded()), 1),
                        category: candidate.category,
                        description: candidate.description
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.lane == rhs.lane {
                        return lhs.startMilliseconds < rhs.startMilliseconds
                    }

                    return lhs.lane < rhs.lane
                }

        guard !spans.isEmpty else { return nil }

        let durationMilliseconds = spans.map { $0.startMilliseconds + $0.durationMilliseconds }.max() ?? 0

        return BazelBuildTimelineTelemetry(
            durationMilliseconds: durationMilliseconds,
            laneLabels: laneLabels,
            spans: spans
        )
    }

    private func criticalPathThreadIdentifier(in events: [[String: Any]]) -> Int? {
        events.first { event in
            string(event["name"]) == "thread_name" &&
                string((event["args"] as? [String: Any])?["name"]) == "Critical Path"
        }
        .flatMap { integer($0["tid"]) }
    }

    private func action(from event: [String: Any]) -> (timestamp: Double, action: BazelCriticalPathActionTelemetry)? {
        guard let description = sanitizedDescription(string(event["name"])),
              let microseconds = decimal(event["dur"]),
              microseconds >= 0
        else {
            return nil
        }

        return (
            timestamp: decimal(event["ts"]) ?? 0,
            action: BazelCriticalPathActionTelemetry(
                description: description,
                durationMilliseconds: max(Int((microseconds / 1000).rounded()), 1)
            )
        )
    }

    private func timelineCandidate(from event: [String: Any]) -> TimelineCandidate? {
        guard string(event["ph"]) == "X",
              let threadIdentifier = integer(event["tid"]),
              let timestampMicroseconds = decimal(event["ts"]),
              let durationMicroseconds = decimal(event["dur"]),
              durationMicroseconds >= Double(Self.minimumTimelineSpanDurationMicroseconds),
              let description = sanitizedDescription(string(event["name"]))
        else {
            return nil
        }

        return TimelineCandidate(
            threadIdentifier: threadIdentifier,
            timestampMicroseconds: timestampMicroseconds,
            durationMicroseconds: Int(durationMicroseconds.rounded()),
            category: timelineCategory(for: string(event["cat"]), description: description),
            description: description
        )
    }

    private func timelineCategory(for category: String?, description: String) -> String {
        let value = (category ?? "").lowercased()
        let lowercasedDescription = description.lowercased()

        if value.contains("critical") {
            return "critical_path"
        } else if value.contains("action") || lowercasedDescription.hasPrefix("action '") {
            return "execution"
        } else if value.contains("analysis") || value.contains("skyframe") {
            return "analysis"
        } else if value.contains("load") || value.contains("package") {
            return "loading"
        } else if value.contains("remote") || value.contains("setup") || value.contains("workspace") {
            return "setup"
        } else {
            return "other"
        }
    }

    private func sanitizedDescription(_ value: String?) -> String? {
        guard var value else { return nil }

        value = value.replacingOccurrences(
            of: "(^|[\\s'=\\\"])((?:/(?!/)|~/|[A-Za-z]:\\\\)\\S+)",
            with: "$1<redacted>",
            options: .regularExpression
        )
        value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !value.isEmpty,
              value.count <= Self.maximumActionDescriptionLength,
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else {
            return nil
        }

        return value
    }

    private func string(_ value: Any?) -> String? {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            number.intValue
        case let value as String:
            Int(value)
        default:
            nil
        }
    }

    private func decimal(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            number.doubleValue
        case let value as String:
            Double(value)
        default:
            nil
        }
    }
}

private struct TimelineCandidate {
    let threadIdentifier: Int
    let timestampMicroseconds: Double
    let durationMicroseconds: Int
    let category: String
    let description: String
}
