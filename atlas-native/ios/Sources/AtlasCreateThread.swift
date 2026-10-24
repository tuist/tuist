import SwiftUI

struct AtlasCreateThread: View {
    @ObservedObject var model: AtlasOrbit
    let people: [AtlasPerson]
    let created: (AtlasThread) -> Void
    @State private var title = ""
    @State private var participants: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Purpose") { TextField("Thread title", text: $title).disabled(model.creating) }
                Section {
                    ForEach(people) { person in
                        Toggle(person.name, isOn: Binding(get: { participants.contains(person.id) }, set: { value in
                            if value { participants.insert(person.id) } else { participants.remove(person.id) }
                        })).disabled(model.creating)
                    }
                } header: { Text("Participants") } footer: {
                    Text("Only participants can read this thread. The server checks access before tools are used.")
                }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("New shared thread").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.creating) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if let thread = await model.create(title: title, participants: Array(participants)) {
                                created(thread)
                            }
                        }
                    }.disabled(model.creating || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(model.creating)
            .protectsAtlasNavigation(model.creating || !title.isEmpty)
        }
    }
}
