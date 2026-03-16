public struct Target: Encodable, Sendable {
    public let name: String
    public let project: String
    public let build_duration: Int
    public let compilation_duration: Int
    public let status: String
}
