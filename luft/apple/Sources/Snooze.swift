import SwiftUI

/// A thread's snooze, decided by the Rust core: until a time, or until its run stops.
struct AppSnooze: Decodable, Equatable {
    let until: String?
    let until_needed: Bool

    var untilDate: Date? { until.flatMap { ISO8601DateFormatter().date(from: $0) } }

    /// "Until I'm needed", or the time it ends.
    var label: String {
        guard let date = untilDate else { return String(localized: "Snoozed until needed") }
        return String(format: String(localized: "Snoozed until %@"), SnoozeChoices.format(date))
    }
}

/// What Snooze offers now, from the core's `snooze_options`. Refreshed every
/// minute while a screen shows it, so "In 1 hour" and "This evening" stay true.
@MainActor @Observable
final class SnoozeChoices {
    struct Option: Decodable, Identifiable {
        let id: String
        let until: String?
    }

    private(set) var options: [Option] = []

    func follow(_ client: AppClient) async {
        while !Task.isCancelled {
            let args: [String: Any] = ["offset_seconds": TimeZone.current.secondsFromGMT(), "working": true]
            if let data = try? await client.call("snooze_options", args),
               let list = data["options"],
               let decoded = try? JSONDecoder().decode([Option].self, from: JSONSerialization.data(withJSONObject: list))
            { options = decoded }
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// The options for a thread: waiting until it's needed only while it works.
    func available(working: Bool) -> [Option] {
        options.filter { working || $0.id != "until_needed" }
    }

    nonisolated static func title(_ option: Option) -> String {
        switch option.id {
        case "until_needed": String(localized: "Until I'm needed")
        case "in_1_hour": String(localized: "In 1 hour")
        case "in_2_hours": String(localized: "In 2 hours")
        case "in_4_hours": String(localized: "In 4 hours")
        case "this_evening": String(localized: "This evening")
        case "tomorrow": String(localized: "Tomorrow")
        case "next_week": String(localized: "Next week")
        default: option.id
        }
    }

    /// When the option ends, for its subtitle.
    nonisolated static func subtitle(_ option: Option) -> String? {
        guard option.id != "until_needed" else { return String(localized: "When it replies or stops") }
        return option.until.flatMap { ISO8601DateFormatter().date(from: $0) }.map(format)
    }

    /// "18:00", "Thu 09:00" or "Nov 24, 09:00": as short as the day allows.
    nonisolated static func format(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if let week = calendar.date(byAdding: .day, value: 6, to: .now), date < week {
            return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}

/// The buttons Snooze shows in a menu or dialog: the core's options, a custom
/// time, and Wake now for a thread that's snoozed.
struct SnoozeButtons: View {
    let choices: SnoozeChoices
    let working: Bool
    let snoozed: Bool
    /// Dialogs show one line per button, so the time goes after the title there.
    var inline = false
    let snooze: (String?) -> Void
    let custom: () -> Void

    var body: some View {
        ForEach(choices.available(working: working)) { option in
            Button { snooze(option.until ?? "until_needed") } label: {
                if inline {
                    Text(verbatim: [SnoozeChoices.title(option), option.until == nil ? nil : SnoozeChoices.subtitle(option)]
                        .compactMap { $0 }.joined(separator: " · "))
                } else {
                    Text(verbatim: SnoozeChoices.title(option))
                    if let subtitle = SnoozeChoices.subtitle(option) { Text(verbatim: subtitle) }
                }
            }
        }
        Button("Pick a time…") { custom() }
        if snoozed {
            Button("Wake now", systemImage: "sun.max") { snooze(nil) }
        }
    }
}

/// Snoozes until a time the person picks, up to 30 days ahead.
struct CustomSnoozeView: View {
    let snooze: (String) -> Void
    @State private var date = Date.now.addingTimeInterval(2 * 3600)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Remind me",
                    selection: $date,
                    in: Date.now.addingTimeInterval(60) ... Date.now.addingTimeInterval(30 * 86400)
                )
                #if os(iOS)
                .datePickerStyle(.graphical)
                #endif
            }
            .navigationTitle("Snooze until")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Snooze") {
                            snooze(ISO8601DateFormatter().string(from: date))
                            dismiss()
                        }
                    }
                }
        }
        #if os(macOS)
        .frame(width: 360, height: 220)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }
}

extension AppClient {
    /// Snoozes thread `id` until `until` (`until_needed`, a time, or nil to wake it).
    func snooze(_ id: String, until: String?) async throws -> AppConversation {
        try await conversation("snooze_thread", ["id": id, "snooze": until.map { $0 as Any } ?? NSNull()])
    }
}
