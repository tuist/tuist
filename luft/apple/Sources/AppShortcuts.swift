import Combine

/// Hands an App Shortcut's route from App Intents to the workspace, which sends
/// it to the core like a link. Only iOS offers shortcuts.
/// This file must compile on its own: `modules/appintents.sh` extracts the
/// Shortcuts metadata from it, because Struo does not run Xcode's App Intents step.
@MainActor
final class ShortcutInbox: ObservableObject {
    static let shared = ShortcutInbox()
    @Published var path: String?
}

#if os(iOS)
    import AppIntents

    struct StartConversationIntent: AppIntent {
        static let title: LocalizedStringResource = "Start Conversation"
        static let description = IntentDescription("Opens a new conversation, ready to type.")
        static let openAppWhenRun = true

        @MainActor func perform() async throws -> some IntentResult {
            ShortcutInbox.shared.path = "/threads/new"
            return .result()
        }
    }

    struct DictateConversationIntent: AppIntent {
        static let title: LocalizedStringResource = "Dictate Conversation"
        static let description = IntentDescription(
            "Opens a new conversation and starts dictation on this device. Nothing is sent until you tap Start."
        )
        static let openAppWhenRun = true

        @MainActor func perform() async throws -> some IntentResult {
            ShortcutInbox.shared.path = "/threads/new/dictation"
            return .result()
        }
    }

    struct LuftShortcuts: AppShortcutsProvider {
        static var appShortcuts: [AppShortcut] {
            AppShortcut(
                intent: StartConversationIntent(),
                phrases: ["Start a conversation in \(.applicationName)"],
                shortTitle: "Start Conversation",
                systemImageName: "square.and.pencil"
            )
            AppShortcut(
                intent: DictateConversationIntent(),
                phrases: ["Dictate a conversation in \(.applicationName)"],
                shortTitle: "Dictate Conversation",
                systemImageName: "mic"
            )
        }
    }
#endif
