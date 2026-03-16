public struct CASOutput: Encodable, Sendable {
    public let node_id: String
    public let checksum: String
    public let size: Int
    public let duration: Double
    public let compressed_size: Int
    public let operation: String
    public let type: String?
}
