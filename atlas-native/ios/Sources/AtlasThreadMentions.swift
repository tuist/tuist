import SwiftUI

struct AtlasThreadMentions: View {
    @ObservedObject var model: AtlasOrbit
    let shared: Bool
    @State private var searching = false

    private var query: String? {
        guard let at = model.draft.lastIndex(of: "@"),
              at == model.draft.startIndex || model.draft[model.draft.index(before: at)].isWhitespace else { return nil }
        let suffix = String(model.draft[model.draft.index(after: at)...])
        guard suffix.count <= 80, !suffix.contains("\n"),
              !model.draftMentions.contains(where: { suffix == $0.name + " " }) else { return nil }
        return suffix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if query != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.mentionCandidates) { person in
                            Button {
                                Task { await model.mention(person) }
                            } label: {
                                Label(person.name, systemImage: "person.crop.circle")
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("thread-mention-\(person.id)")
                        }
                        if searching { ProgressView("Finding people…") }
                        if !searching, model.mentionCandidates.isEmpty { Text("No eligible people found").foregroundStyle(.secondary) }
                    }
                }
                .frame(maxHeight: 160)
            }
            if !model.draftMentions.isEmpty {
                Text(shared ? "Tagged people will receive a notification."
                     : "Sending will share this conversation and its history with the tagged people.")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("thread-mention-disclosure")
            }
        }
        .task(id: query) {
            guard let query else { return }
            searching = true
            defer { searching = false }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !Task.isCancelled else { return }
            await model.searchPeople(query: query)
        }
    }
}
