import ActivityKit
import SwiftUI

struct AtlasLiveActivityPreview: View {
    @State private var count = 1
    @State private var phase = AtlasActivityAttributes.Conversation.Status.usingTools
    @State private var stale = false
    @State private var activity: Activity<AtlasActivityAttributes>?
    @State private var message = "Demo data · No network or inference"
    private let attributes = AtlasActivityAttributes(
        registrationID: "01922cc0-0000-7000-8000-000000000099", server: "https://atlas.example.org/"
    )
    @State private var started = Date().addingTimeInterval(-74)

    private var state: AtlasActivityAttributes.ContentState {
        let titles = ["Plan the Lisbon offsite", "Review the launch checklist", "Prepare the weekly update"]
        let longTitle = "Plan the Lisbon offsite and compare travel options for the whole team"
        let conversations: [AtlasActivityAttributes.Conversation] = (0..<min(count, 3)).map { index in
            let id = String(format: "01922cc0-0000-7000-8000-%012d", index + 1)
            let startedAt = started.timeIntervalSince1970 + Double(index * 12)
            let title = index == 0 && ProcessInfo.processInfo.arguments.contains("--long-activity-title")
                ? longTitle : titles[index]
            return .init(id: id, status: index == 0 ? phase : .running,
                         startedAt: startedAt, completedSteps: index == 0 ? 7 : 2, title: title)
        }
        return .init(activeCount: count, conversations: conversations, updatedAt: Date().timeIntervalSince1970)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AtlasActivityView(attributes: attributes, state: state, stale: stale, ended: count == 0)
                        .background(.black, in: RoundedRectangle(cornerRadius: 24))
                        .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                Section("Fixture controls") {
                    Stepper("\(count) conversations", value: $count, in: 0...5).accessibilityIdentifier("activity-count")
                    Picker("Phase", selection: $phase) {
                        Text("Queued").tag(AtlasActivityAttributes.Conversation.Status.queued)
                        Text("Thinking").tag(AtlasActivityAttributes.Conversation.Status.running)
                        Text("Using tools").tag(AtlasActivityAttributes.Conversation.Status.usingTools)
                        Text("Compacting").tag(AtlasActivityAttributes.Conversation.Status.compacting)
                    }
                    Toggle("Stale", isOn: $stale)
                    Button("Start Live Activity") { Task { await start() } }.disabled(count == 0)
                    Button("Update Live Activity") { Task { await update() } }.disabled(activity == nil)
                    Button("End Live Activity") { Task { await end() } }.disabled(activity == nil)
                    Text(message).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("activity-result")
                }
            }.navigationTitle("Pip Live Activity")
        }
    }

    private func start() async {
        await end()
        do {
            // Fixture requests no remote token and never contacts APNs or Atlas.
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            message = "Live Activity started · Demo data"
        } catch { message = "Could not start: \(error.localizedDescription)" }
    }

    private var content: ActivityContent<AtlasActivityAttributes.ContentState> {
        .init(state: state, staleDate: Date().addingTimeInterval(stale ? -1 : 90))
    }

    private func update() async {
        await activity?.update(content)
        message = "Live Activity updated · Demo data"
    }

    private func end() async {
        for activity in Activity<AtlasActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
        activity = nil
        message = "Live Activity ended · Demo data"
    }
}
