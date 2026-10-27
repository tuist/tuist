import SwiftUI

struct AtlasSharedItemsView: View {
    @ObservedObject var model: AtlasSharedItems
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack {
            Group {
                if let draft = model.draft {
                    editor(draft)
                } else {
                    List {
                        if model.items.isEmpty {
                            ContentUnavailableView("No shared items", systemImage: "square.and.arrow.down",
                                                   description: Text("Share a link or text from another app and choose Atlas."))
                        }
                        ForEach(model.items) { item in
                            Button { model.select(item) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title.isEmpty ? (item.url.isEmpty ? "Shared text" : item.url) : item.title)
                                        .foregroundStyle(.primary).lineLimit(2)
                                    Text(item.submitted ? "Save awaiting confirmation" : "Saved on this device · Not yet in Moodboard")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.frame(minHeight: 44)
                            }
                        }
                        if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                    }
                    .navigationTitle("Shared items")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.draft == nil ? "Done" : "Back") {
                        if model.draft == nil { dismiss() } else { model.leaveEditor() }
                    }.disabled(model.saving)
                }
            }
        }
        .interactiveDismissDisabled(model.saving)
        .onDisappear { model.leaveEditor() }
        .protectsAtlasNavigation(true)
    }

    private func editor(_ capture: AtlasShareCapture) -> some View {
        Form {
            Section {
                if !capture.url.isEmpty { Text(capture.url).textSelection(.enabled) }
                if !capture.content.isEmpty {
                    DisclosureGroup("Shared text") { Text(capture.content).textSelection(.enabled) }
                }
            } header: { Text("Source") } footer: {
                Text("Atlas fetches public link details and sends source text to its configured AI provider to suggest fields. " +
                     "Nothing is added to the team's shared Moodboard until you save.")
            }
            Section("Review fields") {
                TextField("Title", text: field(\.title)).accessibilityIdentifier("share-title")
                TextField("Description", text: field(\.description), axis: .vertical).lineLimit(3...8)
                TextField("Tags, separated by commas", text: Binding(
                    get: { model.draft?.tags.joined(separator: ", ") ?? "" },
                    set: { model.draft?.tags = $0.components(separatedBy: ",") }
                )).autocorrectionDisabled().textInputAutocapitalization(.never)
            }.disabled(capture.submitted || model.saving)
            Section {
                if model.suggesting { ProgressView("Suggesting fields…") }
                if let message = model.suggestionMessage { Text(message).font(.footnote).foregroundStyle(.secondary) }
                if capture.submitted {
                    Text("The previous save has not been confirmed. Retry sends exactly the same fields so it cannot create a duplicate.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                Button { Task { await model.save() } } label: {
                    HStack {
                        if model.saving { ProgressView() }
                        Text(capture.submitted ? "Retry save" : "Save to Moodboard")
                    }.frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(model.saving || capture.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("share-save")
                Button("Discard local share", role: .destructive) { confirmDiscard = true }.disabled(model.saving)
            }
        }
        .navigationTitle("Review shared item")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: capture.id) { await model.suggest() }
        .confirmationDialog("Discard this local share?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard local share", role: .destructive) { model.discard() }
        } message: { Text("This removes the copy on this device. It does not delete anything already saved to Moodboard.") }
    }

    private func field(_ key: WritableKeyPath<AtlasShareCapture, String>) -> Binding<String> {
        Binding(get: { model.draft?[keyPath: key] ?? "" }, set: { model.draft?[keyPath: key] = $0 })
    }
}

struct AtlasSharedItemsPresentation: ViewModifier {
    var model: AtlasSharedItems?
    let protectedWork: Bool

    func body(content: Content) -> some View {
        if let model {
            content.modifier(SharedItemsPresentation(model: model, protectedWork: protectedWork))
        } else { content }
    }
}

private struct SharedItemsPresentation: ViewModifier {
    @ObservedObject var model: AtlasSharedItems
    let protectedWork: Bool

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if !model.items.isEmpty, !protectedWork, !model.presented {
                    Button { model.presented = true } label: {
                        Label("Review shared items (\(model.items.count))", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.background(.regularMaterial)
                }
            }
            .sheet(isPresented: $model.presented) { AtlasSharedItemsView(model: model) }
    }
}
