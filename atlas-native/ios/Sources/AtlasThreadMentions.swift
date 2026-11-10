import SwiftUI

struct AtlasThreadMentions: View {
    @ObservedObject var model: AtlasOrbit
    let shared: Bool
    @State private var searching = false
    @State private var completedQuery: String?
    @State private var contentHeight: CGFloat = 52

    private var query: String? {
        guard let at = model.draft.lastIndex(of: "@"),
              at == model.draft.startIndex || model.draft[model.draft.index(before: at)].isWhitespace else { return nil }
        let suffix = String(model.draft[model.draft.index(after: at)...])
        guard suffix.utf8.count <= 100, !suffix.contains("\n"),
              !suffix.hasPrefix("Pip "),
              !model.draftMentions.contains(where: { suffix.hasPrefix($0.name + " ") }) else { return nil }
        return suffix
    }

    private var offersPip: Bool { query.map { "pip".hasPrefix($0.lowercased()) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if query != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if offersPip {
                            Button {
                                guard let at = model.draft.lastIndex(of: "@") else { return }
                                model.draft.replaceSubrange(at..., with: "@Pip ")
                            } label: {
                                suggestion("Pip", assistant: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("thread-mention-pip")
                            if searching || completedQuery == query && (!model.mentionCandidates.isEmpty || model.mentionError != nil) {
                                Divider().padding(.leading, 60)
                            }
                        }
                        ForEach(completedQuery == query ? model.mentionCandidates : []) { person in
                            Button {
                                Task { await model.mention(person) }
                            } label: {
                                suggestion(person.name)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("thread-mention-\(person.id)")
                            if person.id != model.mentionCandidates.last?.id { Divider().padding(.leading, 60) }
                        }
                        if searching { ProgressView("Finding people…").padding(12) }
                        if !searching, completedQuery == query {
                            if let error = model.mentionError {
                                Text(error).foregroundStyle(.secondary).padding(12)
                            } else if model.mentionCandidates.isEmpty, !offersPip {
                                Text("No eligible people found").foregroundStyle(.secondary).padding(12)
                            }
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .frame(height: min(contentHeight, 200))
                .scrollBounceBehavior(.basedOnSize)
                .background(.background, in: RoundedRectangle(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.quaternary, lineWidth: 0.5) }
                .accessibilityIdentifier("thread-mention-suggestions")
            }
            if !model.draftMentions.isEmpty {
                Text(shared ? "Tagged people will receive a notification."
                     : "Sending will share this conversation and its history with the tagged people.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("thread-mention-disclosure")
            }
        }
        .task(id: query) {
            guard let query else { searching = false; completedQuery = nil; return }
            searching = true
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !Task.isCancelled else { return }
            await model.searchPeople(query: query)
            guard !Task.isCancelled else { return }
            completedQuery = query
            searching = false
        }
    }

    private func suggestion(_ name: String, assistant: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined())
                .font(.subheadline.weight(.semibold)).foregroundStyle(assistant ? Color.purple : Color.accentColor)
                .frame(width: 36, height: 36)
                .background((assistant ? Color.purple : Color.accentColor).opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).foregroundStyle(.primary)
                if assistant { Text("Assistant").font(.caption).foregroundStyle(.secondary) }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }
}
