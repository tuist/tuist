public struct CacheableTask: Encodable, Sendable {
    public let type: String
    public let status: String
    public let key: String
    public let read_duration: Double?
    public let write_duration: Double?
    public let description: String?
    public let cas_output_node_ids: [String]
}
