import FileSystem
import Foundation
import Mockable
import Path

/// Metadata persisted after a `tuist generate` so that a later `tuist inspect build` can link a
/// local Xcode build back to the graph the generation already uploaded to the server.
public struct GenerationMetadata: Codable, Equatable, Sendable {
    public let generationId: String
    public let generatedAt: Date

    public init(generationId: String, generatedAt: Date) {
        self.generationId = generationId
        self.generatedAt = generatedAt
    }
}

@Mockable
public protocol GenerationMetadataStoring {
    /// Persists the `generationId` for the project at `projectPath`, overwriting any previous entry.
    func store(generationId: String, for projectPath: AbsolutePath) async throws
    /// Returns the last persisted `generationId` for the project at `projectPath`, if any.
    func read(for projectPath: AbsolutePath) async throws -> String?
    /// Removes entries older than the retention window so the cache doesn't grow unbounded.
    func prune() async throws
}

public struct GenerationMetadataStore: GenerationMetadataStoring {
    private let cacheDirectoriesProvider: CacheDirectoriesProviding
    private let contentHasher: ContentHashing
    private let fileSystem: FileSysteming

    private static let retention: TimeInterval = 60 * 60 * 24 * 30

    public init(
        cacheDirectoriesProvider: CacheDirectoriesProviding = CacheDirectoriesProvider(),
        contentHasher: ContentHashing = ContentHasher(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.contentHasher = contentHasher
        self.fileSystem = fileSystem
    }

    public func store(generationId: String, for projectPath: AbsolutePath) async throws {
        let path = try metadataPath(for: projectPath)
        let directory = path.parentDirectory
        if try await !fileSystem.exists(directory) {
            try await fileSystem.makeDirectory(at: directory)
        }
        if try await fileSystem.exists(path) {
            try await fileSystem.remove(path)
        }
        let metadata = GenerationMetadata(generationId: generationId, generatedAt: Date())
        try await fileSystem.writeAsJSON(metadata, at: path)
    }

    public func read(for projectPath: AbsolutePath) async throws -> String? {
        let path = try metadataPath(for: projectPath)
        guard try await fileSystem.exists(path) else { return nil }
        let metadata: GenerationMetadata = try await fileSystem.readJSONFile(at: path)
        return metadata.generationId
    }

    public func prune() async throws {
        let directory = try cacheDirectoriesProvider.cacheDirectory(for: .generationMetadata)
        guard try await fileSystem.exists(directory) else { return }
        let cutoff = Date().addingTimeInterval(-Self.retention)
        let files = try await fileSystem.glob(directory: directory, include: ["*.json"]).collect()
        for file in files {
            guard let metadata: GenerationMetadata = try? await fileSystem.readJSONFile(at: file) else {
                try? await fileSystem.remove(file)
                continue
            }
            if metadata.generatedAt < cutoff {
                try? await fileSystem.remove(file)
            }
        }
    }

    private func metadataPath(for projectPath: AbsolutePath) throws -> AbsolutePath {
        let hash = try contentHasher.hash(projectPath.pathString)
        return try cacheDirectoriesProvider.cacheDirectory(for: .generationMetadata)
            .appending(component: "\(hash).json")
    }
}
