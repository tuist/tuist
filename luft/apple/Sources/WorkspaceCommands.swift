import SwiftUI

/// The menu bar's commands on macOS and iPadOS, so New and the tab shortcuts
/// are listed and discoverable instead of living only in toolbars.
struct WorkspaceCommands: Commands {
    @FocusedValue(\.selectTab) private var selectTab
    @FocusedValue(\.compose) private var compose
    @FocusedValue(\.commandPalette) private var commandPalette
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(compose?.title ?? "New Conversation") { compose?.perform() }
                .keyboardShortcut("n")
                .disabled(compose == nil)
            if supportsMultipleWindows {
                // ⌘N starts a conversation, as in Mail and Messages.
                Button("New Window") { openWindow(id: WorkspaceCommands.window) }
                    .keyboardShortcut("n", modifiers: [.command, .option])
            }
        }
        CommandGroup(before: .sidebar) {
            // ⌘K, as in Slack and the Tuist dashboard.
            Button("Jump To…") { commandPalette?.perform() }
                .keyboardShortcut("k")
                .disabled(commandPalette == nil)
            Divider()
            ForEach(Array([AppNavigation.Tab.threads, .lounges, .dms, .ops, .profile].enumerated()), id: \.offset) { index, tab in
                Button(tab.title) { selectTab?.perform(tab) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .disabled(selectTab == nil)
            }
            Divider()
        }
    }

    static let window = "workspace"
}

extension AppNavigation.Tab {
    var title: LocalizedStringKey {
        switch self {
        case .threads: "Threads"
        case .lounges: "Lounges"
        case .dms: "DMs"
        case .profile: "Profile"
        case .ops: "Ops"
        }
    }
}

struct SelectTabAction {
    let perform: (AppNavigation.Tab) -> Void
}

/// Starts a lounge or a direct conversation, depending on the tab that is open.
struct ComposeAction {
    let title: LocalizedStringKey
    let perform: () -> Void
}

private struct SelectTabKey: FocusedValueKey {
    typealias Value = SelectTabAction
}

private struct ComposeKey: FocusedValueKey {
    typealias Value = ComposeAction
}

extension FocusedValues {
    var selectTab: SelectTabAction? {
        get { self[SelectTabKey.self] }
        set { self[SelectTabKey.self] = newValue }
    }

    var compose: ComposeAction? {
        get { self[ComposeKey.self] }
        set { self[ComposeKey.self] = newValue }
    }
}
