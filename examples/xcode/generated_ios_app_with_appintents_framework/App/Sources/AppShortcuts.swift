import AppIntents
import IntentsFramework

@available(iOS 17.0, *)
struct SampleAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenSearchIntent(),
            phrases: [
                "Search on \(.applicationName)",
            ],
            shortTitle: "Search",
            systemImageName: "magnifyingglass"
        )
    }
}
