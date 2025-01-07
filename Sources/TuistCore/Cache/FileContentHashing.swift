import Path

public protocol FileContentHashing {
    func hash(path: AbsolutePath) async throws -> String
}
