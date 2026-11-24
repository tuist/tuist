import SwiftUI

/// The session metadata already returned by the core, separate from its messages.
struct SessionDetails: View {
    let thread: AppConversation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Overview") {
                    if let title = thread.title, !title.isEmpty {
                        Text(verbatim: title).font(.headline)
                    }
                    if let goal = thread.goal, !goal.isEmpty {
                        LabeledContent("Original request") { Text(verbatim: goal) }
                    }
                    LabeledContent("Status") {
                        switch thread.state {
                        case "queued": Text("Queued")
                        case "running": Text("Running")
                        case "completed": Text("Ready to review")
                        case "failed": Text("Needs attention")
                        case "outcome_unknown": Text("Outcome unknown")
                        default: Text("Unknown")
                        }
                    }
                    if thread.section == "archived" {
                        Text("Archived")
                    }
                    if let snooze = thread.snooze {
                        Text(verbatim: snooze.label)
                    }
                }
                Section("Configuration") {
                    if let provider = thread.provider, !provider.isEmpty {
                        LabeledContent("Provider") { Text(verbatim: provider) }
                    }
                    if let model = thread.model, !model.isEmpty {
                        LabeledContent("Model") { Text(verbatim: model) }
                    }
                    if let repository = thread.repository, !repository.isEmpty {
                        LabeledContent("Repository") { Text(verbatim: repository) }
                    }
                    if let branch = thread.branch, !branch.isEmpty {
                        LabeledContent("Branch") { Text(verbatim: branch) }
                    }
                    if let runner = thread.runner_id, !runner.isEmpty {
                        LabeledContent("Runner ID") { Text(verbatim: runner) }
                    }
                    LabeledContent("Session ID") { Text(verbatim: thread.id) }
                }
                Section("People") {
                    if let owner = thread.owner {
                        LabeledContent("Owner") { Text(verbatim: owner.handle ?? String(owner.id)) }
                    }
                    ForEach(thread.participants ?? []) { person in
                        Text(verbatim: person.handle ?? String(person.id))
                    }
                    if thread.participants?.isEmpty == true {
                        Text("Private conversation")
                    }
                }
            }
            .textSelection(.enabled)
            .navigationTitle("Session details")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
            .frame(minWidth: 440, idealWidth: 520, minHeight: 480, idealHeight: 600)
        #endif
    }
}
