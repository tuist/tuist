public struct TuistTomlConfig: Codable, Equatable, Sendable {
    public let project: String
    public let url: String?

    public init(
        project: String,
        url: String? = nil
    ) {
        self.project = project
        self.url = url
    }
}
