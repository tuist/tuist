import Path

public protocol FileContentHashing: Sendable {
    func hash(path: AbsolutePath) async throws -> String
}
