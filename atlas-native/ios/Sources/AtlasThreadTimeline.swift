import SwiftUI

struct AtlasThreadTimeline: View {
    let messages: [AtlasThreadMessage]
    let selfId: String?
    let openAttachment: (AtlasThreadAttachment) -> Void
    let action: (String, String) async -> Bool

    private struct Group: Identifiable {
        let id: String
        var messages: [AtlasThreadMessage]
        var tools: Bool { messages.count > 1 && messages.allSatisfy { $0.kind == "tool" } }
    }

    private var children: [String: [AtlasThreadMessage]] {
        let parents = Set(messages.filter { $0.kind == "tool" && $0.parentMessageId == nil }.map(\.id))
        return messages.reduce(into: [:]) { result, message in
            if message.kind == "tool", let parent = message.parentMessageId, parents.contains(parent) {
                result[parent, default: []].append(message)
            }
        }
    }

    private var groups: [Group] {
        var result: [Group] = []
        let children = self.children
        let nested = Set(children.values.flatMap { $0.map(\.id) })
        for message in messages where !nested.contains(message.id) {
            let last = result.last?.messages.last
            if message.kind == "tool", message.component?.type != "account_card",
               last?.kind == "tool", last?.component?.type != "account_card",
               children[message.id] == nil, last.map({ children[$0.id] == nil }) == true,
               sameDay(message.insertedAt, last?.insertedAt) {
                result[result.count - 1].messages.append(message)
            } else {
                result.append(Group(id: message.id, messages: [message]))
            }
        }
        return result
    }

    var body: some View {
        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
            if let first = group.messages.first {
                if index == 0 || !sameDay(first.insertedAt, groups[index - 1].messages.last?.insertedAt),
                   let date = ISO8601DateFormatter().date(from: first.insertedAt) {
                    Text(date, format: .dateTime.month(.abbreviated).day().year())
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.vertical, 8)
                }
                if let nested = children[first.id] {
                    AtlasToolActivity(messages: nested, selfId: selfId, parent: first, action: action)
                } else if group.tools {
                    AtlasToolActivity(messages: group.messages, selfId: selfId, action: action)
                } else {
                    AtlasThreadMessageView(message: first, selfId: selfId, openAttachment: openAttachment) { event in
                        await action(first.id, event)
                    }
                    .id(first.id)
                }
            }
        }
    }

    private func sameDay(_ current: String, _ previous: String?) -> Bool {
        guard let previous, let date = ISO8601DateFormatter().date(from: current),
              let prior = ISO8601DateFormatter().date(from: previous) else { return false }
        return Calendar.current.isDate(date, inSameDayAs: prior)
    }
}

struct AtlasThreadNavigation: View {
    let messages: [AtlasThreadMessage]
    let shared: Bool
    let hasOlder: Bool
    let loading: Bool
    let showsLatest: Bool
    let older: () async -> Void
    let jump: (String) -> Void
    @State private var showingPrompts = false

    private var prompts: [AtlasThreadMessage] { messages.filter { $0.kind == "human" } }

    var body: some View {
        if !prompts.isEmpty || hasOlder || showsLatest {
            HStack(spacing: 0) {
                if !prompts.isEmpty || hasOlder {
                    Button("Conversation prompts", systemImage: "list.bullet") { showingPrompts = true }
                        .frame(width: 44, height: 44)
                        .accessibilityHint("Choose a prompt to jump back to it")
                        .accessibilityIdentifier("thread-prompts")
                        .popover(isPresented: $showingPrompts) { promptList }
                }
                if showsLatest {
                    if !prompts.isEmpty || hasOlder { Divider().frame(height: 20) }
                    Button("Latest messages", systemImage: "arrow.down") { jump("thread-latest") }
                        .frame(width: 44, height: 44)
                }
            }
            .labelStyle(.iconOnly).buttonStyle(.borderless)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(.primary.opacity(0.12)) }
        }
    }

    private var promptList: some View {
        NavigationStack {
            List {
                if hasOlder {
                    Button(loading ? "Loading earlier prompts…" : "Load earlier prompts") { Task { await older() } }
                        .disabled(loading).frame(minHeight: 44)
                }
                if prompts.isEmpty { Text("No prompts in loaded history.").foregroundStyle(.secondary) }
                ForEach(prompts) { message in
                    Button {
                        showingPrompts = false
                        jump(message.id)
                    } label: {
                        promptRow(message)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Jump to this message")
                    .accessibilityIdentifier("thread-prompt-\(message.id)")
                }
            }
            .navigationTitle("Prompts").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingPrompts = false } } }
        }
        .frame(idealWidth: 380, idealHeight: 440)
        .presentationDetents([.medium, .large])
        .presentationCompactAdaptation(.sheet)
    }

    private func promptRow(_ message: AtlasThreadMessage) -> some View {
        let body = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = (message.attachments ?? []).map(\.filename).joined(separator: ", ")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: message.insertedAt) ?? ISO8601DateFormatter().date(from: message.insertedAt)
        return VStack(alignment: .leading, spacing: 4) {
            Text(body.isEmpty ? (files.isEmpty ? "Message" : files) : body).lineLimit(2).multilineTextAlignment(.leading)
            HStack {
                if shared { Text(message.authorName) }
                if let date { Text(date, style: .relative) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct AtlasToolActivity: View {
    let messages: [AtlasThreadMessage]
    let selfId: String?
    var parent: AtlasThreadMessage?
    let action: (String, String) async -> Bool
    @State private var expanded = false

    private var running: Bool { parent?.toolStatus == "running" || messages.contains { $0.toolStatus == "running" } }
    private var failed: Int { messages.filter { $0.toolStatus == "failed" }.count + (parent?.toolStatus == "failed" ? 1 : 0) }
    private var symbol: String {
        if running { return "gearshape.2" }
        if failed > 0 { return "exclamationmark.circle" }
        if parent?.toolStatus == "cancelled" || messages.contains(where: { $0.toolStatus == "cancelled" }) { return "minus.circle" }
        return messages.allSatisfy({ $0.toolStatus == "succeeded" }) && (parent == nil || parent?.toolStatus == "succeeded")
            ? "checkmark.circle" : "circle"
    }
    private var summary: String {
        if parent != nil { return "Research task" }
        let count = messages.count
        if running { return "Using \(count) tools…" }
        return "Used \(count) tools"
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                if let parent {
                    AtlasThreadMessageView(message: parent, selfId: selfId) { event in
                        await action(parent.id, event)
                    }
                }
                ForEach(messages) { message in
                    AtlasThreadMessageView(message: message, selfId: selfId) { event in
                        await action(message.id, event)
                    }
                }
            }
            .padding(.leading, 16).padding(.top, 8)
            .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 1) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(failed > 0 ? Color.orange : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary).font(.subheadline.weight(.medium))
                    if let parent {
                        Text("\(messages.count) tool calls · \(parent.toolStatus ?? "Working")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if failed > 0 { Text("\(failed) failed").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
        }
        .accessibilityIdentifier("thread-tool-group-\(parent?.id ?? messages.first?.id ?? "")")
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
