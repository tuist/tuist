import AppIntents

struct AppIntentExtension: AppIntent {
    static var title: LocalizedStringResource = "AppIntentExtension"

    func perform() async throws -> some IntentResult {
        .result()
    }
}
