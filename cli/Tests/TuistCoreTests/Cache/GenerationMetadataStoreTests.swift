import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCore

struct GenerationMetadataStoreTests {
    private let fileSystem = FileSystem()
    private let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
    private let subject: GenerationMetadataStore

    init() {
        subject = GenerationMetadataStore(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            contentHasher: ContentHasher(),
            fileSystem: fileSystem
        )
    }

    @Test(.inTemporaryDirectory) func store_then_read_returns_the_generation_id() async throws {
        // Given
        let directory = try #require(FileSystem.temporaryTestDirectory).appending(component: "GenerationMetadata")
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.generationMetadata))
            .willReturn(directory)
        let projectPath = try AbsolutePath(validating: "/Project/App.xcworkspace")

        // When
        try await subject.store(generationId: "generation-id", for: projectPath)

        // Then
        #expect(try await subject.read(for: projectPath) == "generation-id")
        #expect(try await subject.read(for: AbsolutePath(validating: "/Other/App.xcworkspace")) == nil)
    }

    @Test(.inTemporaryDirectory) func store_overwrites_a_previous_entry() async throws {
        // Given
        let directory = try #require(FileSystem.temporaryTestDirectory).appending(component: "GenerationMetadata")
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.generationMetadata))
            .willReturn(directory)
        let projectPath = try AbsolutePath(validating: "/Project/App.xcworkspace")

        // When
        try await subject.store(generationId: "first", for: projectPath)
        try await subject.store(generationId: "second", for: projectPath)

        // Then
        #expect(try await subject.read(for: projectPath) == "second")
    }

    @Test(.inTemporaryDirectory) func prune_removes_stale_entries_and_keeps_recent_ones() async throws {
        // Given
        let directory = try #require(FileSystem.temporaryTestDirectory).appending(component: "GenerationMetadata")
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.generationMetadata))
            .willReturn(directory)
        try await fileSystem.makeDirectory(at: directory)
        let stalePath = directory.appending(component: "stale.json")
        let recentPath = directory.appending(component: "recent.json")
        try await fileSystem.writeAsJSON(
            GenerationMetadata(generationId: "stale", generatedAt: Date().addingTimeInterval(-60 * 60 * 24 * 40)),
            at: stalePath
        )
        try await fileSystem.writeAsJSON(
            GenerationMetadata(generationId: "recent", generatedAt: Date()),
            at: recentPath
        )

        // When
        try await subject.prune()

        // Then
        #expect(try await fileSystem.exists(stalePath) == false)
        #expect(try await fileSystem.exists(recentPath) == true)
    }
}
