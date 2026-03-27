public struct Issue: Encodable, Sendable {
    public let type: String
    public let target: String
    public let project: String
    public let title: String
    public let signature: String
    public let step_type: String
    public let path: String?
    public let message: String?
    public let starting_line: Int
    public let ending_line: Int
    public let starting_column: Int
    public let ending_column: Int
}
