import AppIntents

@available(iOS 17.0, *)
public struct OpenSearchIntent: AppIntent {
    public init() {}

    public static let title: LocalizedStringResource = "Open Search"
    public static let description = IntentDescription("Opens the search screen.")
    public static let openAppWhenRun = true

    @MainActor
    public func perform() async throws -> some IntentResult {
        return .result()
    }
}
