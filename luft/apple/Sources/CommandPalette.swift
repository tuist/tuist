import SwiftUI

/// One result of the core's `palette`: a destination, New conversation, a thread, a lounge or a DM.
struct PaletteItem: Decodable, Equatable {
    /// `destination`, `action`, `thread`, `lounge` or `dm`, decided by the Rust core.
    let kind: String
    let id: String
    let title: String?
    /// The internal route `navigate` opens.
    let url: String
    let unread: Int?
}

/// ⌘K, as in Slack and the Tuist dashboard: type to jump to a destination, a thread,
/// a lounge or a DM. The core decides what matches; this only draws it and navigates.
struct CommandPalette: View {
    let client: AppClient
    let close: () -> Void
    /// Something was opened from the palette, as opposed to the palette being dismissed.
    var picked: () -> Void = {}
    @State private var query = ""
    @State private var items: [PaletteItem] = []
    @State private var selection: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(Noora.labelSecondary)
                TextField("Jump to a thread, lounge or DM", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { open(items.first { $0.url == selection }) }
                    .onKeyPress(.upArrow) { move(-1) }
                    .onKeyPress(.downArrow) { move(1) }
                    .onKeyPress(.escape) {
                        close()
                        return .handled
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            if items.isEmpty {
                Text("No matches")
                    .foregroundStyle(Noora.labelSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(items, id: \.url) { row($0).id($0.url) }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 380)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: selection) { _, url in
                        if let url { proxy.scrollTo(url) }
                    }
                }
            }
        }
        // Full width less the margins on iPhone, where Search in the sidebar opens it.
        .frame(maxWidth: 580)
        .background(Noora.backgroundPrimary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Noora.border))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
        // Take the keyboard from the reply field the window had. Focus set while the
        // overlay is still being inserted doesn't stick on macOS, so wait a moment.
        .defaultFocus($focused, true)
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            focused = true
        }
        // The core answers from the device, so this runs on every keystroke.
        .task(id: query) { await search() }
        // Lounges and DMs come from the last `lounges` answer; refresh it so they can be found.
        .task {
            _ = try? await client.call("lounges")
            await search()
        }
    }

    private func row(_ item: PaletteItem) -> some View {
        let selected = item.url == selection
        return Button { open(item) } label: {
            HStack(spacing: 10) {
                Image(systemName: icon(item))
                    .frame(width: 20)
                    .foregroundStyle(selected ? Noora.labelPrimary : Noora.labelSecondary)
                Text(verbatim: item.title ?? String(localized: "Untitled"))
                    .lineLimit(1)
                    .foregroundStyle(Noora.labelPrimary)
                Spacer()
                if let unread = item.unread, unread > 0 {
                    Text(verbatim: "\(unread)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Noora.primaryLabel)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Noora.primary, in: Capsule())
                }
                Text(kind(item))
                    .font(.callout)
                    .foregroundStyle(Noora.labelSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
            .background(selected ? Noora.backgroundTertiary : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { if $0 { selection = item.url } }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func icon(_ item: PaletteItem) -> String {
        switch (item.kind, item.id) {
        case ("destination", "threads"): "bubble.left.and.bubble.right"
        case ("destination", "lounges"), ("lounge", _): "number"
        case ("destination", "dms"): "bubble.left.and.text.bubble.right"
        case ("destination", "ops"): "square.stack.3d.up"
        case ("destination", _): "person.crop.circle"
        case ("action", _): "plus"
        case ("dm", _): "person.2"
        default: "bubble.left"
        }
    }

    private func kind(_ item: PaletteItem) -> LocalizedStringKey {
        switch item.kind {
        case "thread": "Thread"
        case "lounge": "Lounge"
        case "dm": "DM"
        case "action": "Action"
        default: "Go to"
        }
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard !items.isEmpty else { return .handled }
        let index = items.firstIndex { $0.url == selection } ?? -step
        selection = items[(index + step + items.count) % items.count].url
        return .handled
    }

    private func search() async {
        let query = query
        let labels = [
            "threads": String(localized: "Threads"),
            "lounges": String(localized: "Lounges"),
            "dms": String(localized: "DMs"),
            "profile": String(localized: "Profile"),
            "ops": String(localized: "Ops"),
            "new_conversation": String(localized: "New conversation"),
        ]
        guard let data = try? await client.call("palette", ["query": query, "labels": labels]),
              let list = data["items"],
              let next = try? JSONDecoder().decode([PaletteItem].self, from: JSONSerialization.data(withJSONObject: list)),
              // A slower answer for an earlier keystroke must not replace a newer one.
              !Task.isCancelled, query == self.query
        else { return }
        items = next
        selection = next.first?.url
    }

    private func open(_ item: PaletteItem?) {
        guard let item else { return }
        close()
        picked()
        if item.id == "new_conversation" {
            client.startConversation()
        } else {
            Task { await client.perform("navigate", ["url": item.url]) }
        }
    }
}

struct CommandPaletteAction {
    let perform: () -> Void
}

private struct CommandPaletteKey: FocusedValueKey {
    typealias Value = CommandPaletteAction
}

extension FocusedValues {
    var commandPalette: CommandPaletteAction? {
        get { self[CommandPaletteKey.self] }
        set { self[CommandPaletteKey.self] = newValue }
    }
}
