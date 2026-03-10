public struct File: Encodable, Sendable {
    public let type: String
    public let target: String
    public let project: String
    public let path: String
    public let compilation_duration: Int
}
