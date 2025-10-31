import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCache
import TuistCore
import TuistServer
import TuistSupport
import XcodeGraph

@testable import TuistCacheEE
@testable import TuistSupport
@testable import TuistTesting

struct CacheStorageTests {
    private var subject: CacheStorage!
    private var localStorage: MockCacheStoring!
    private var remoteStorage: MockCacheStoring!

    init() {
        localStorage = MockCacheStoring()
        remoteStorage = MockCacheStoring()
        subject = CacheStorage(
            localStorage: localStorage,
            remoteStorage: remoteStorage
        )
    }

    @Test(.inTemporaryDirectory)
    func store_returns_remote_results_when_remote_storage_available() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testPath = temporaryDirectory.appending(component: "test.framework")
        try await FileSystem().makeDirectory(at: testPath)

        let items = [CacheStorableItem(name: "target", hash: "hash"): [testPath]]
        let localResult = [CacheStorableItem(name: "target", hash: "hash")]
        let remoteResult = [CacheStorableItem(name: "target", hash: "hash")]

        given(localStorage).store(.any, cacheCategory: .any).willReturn(localResult)
        given(remoteStorage).store(.any, cacheCategory: .any).willReturn(remoteResult)

        // When
        let result = try await subject.store(items, cacheCategory: .binaries)

        // Then
        #expect(result == remoteResult)
        verify(localStorage).store(.any, cacheCategory: .any).called(1)
        verify(remoteStorage).store(.any, cacheCategory: .any).called(1)
    }

    @Test(.inTemporaryDirectory)
    func store_returns_local_results_when_no_remote_storage() async throws {
        // Given
        let localOnlySubject = CacheStorage(localStorage: localStorage, remoteStorage: nil)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testPath = temporaryDirectory.appending(component: "test.framework")
        try await FileSystem().makeDirectory(at: testPath)

        let items = [CacheStorableItem(name: "target", hash: "hash"): [testPath]]
        let localResult = [CacheStorableItem(name: "target", hash: "hash")]

        given(localStorage).store(.any, cacheCategory: .any).willReturn(localResult)

        // When
        let result = try await localOnlySubject.store(items, cacheCategory: .binaries)

        // Then
        #expect(result == localResult)
        verify(localStorage).store(.any, cacheCategory: .any).called(1)
    }

    @Test(.inTemporaryDirectory)
    func store_returns_remote_results_when_local_fails_but_remote_succeeds() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testPath = temporaryDirectory.appending(component: "test.framework")
        try await FileSystem().makeDirectory(at: testPath)

        let items = [CacheStorableItem(name: "target", hash: "hash"): [testPath]]
        let remoteResult = [CacheStorableItem(name: "target", hash: "hash")]

        given(localStorage).store(.any, cacheCategory: .any).willReturn([]) // Local upload failed
        given(remoteStorage).store(.any, cacheCategory: .any).willReturn(remoteResult)

        // When
        let result = try await subject.store(items, cacheCategory: .binaries)

        // Then
        #expect(result == remoteResult)
    }

    @Test(.inTemporaryDirectory)
    func store_returns_partial_remote_results_when_some_remote_uploads_fail() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testPath1 = temporaryDirectory.appending(component: "test1.framework")
        let testPath2 = temporaryDirectory.appending(component: "test2.framework")
        try await FileSystem().makeDirectory(at: testPath1)
        try await FileSystem().makeDirectory(at: testPath2)

        let items = [
            CacheStorableItem(name: "target1", hash: "hash1"): [testPath1],
            CacheStorableItem(name: "target2", hash: "hash2"): [testPath2],
        ]
        let localResult = [
            CacheStorableItem(name: "target1", hash: "hash1"),
            CacheStorableItem(name: "target2", hash: "hash2"),
        ]
        let remoteResult = [CacheStorableItem(name: "target2", hash: "hash2")] // Only target2 succeeded

        given(localStorage).store(.any, cacheCategory: .any).willReturn(localResult)
        given(remoteStorage).store(.any, cacheCategory: .any).willReturn(remoteResult)

        // When
        let result = try await subject.store(items, cacheCategory: .binaries)

        // Then
        #expect(result.count == 1)
        #expect(result.first?.name == "target2")
        #expect(result.first?.hash == "hash2")
    }

    @Test(.inTemporaryDirectory)
    func store_returns_empty_when_all_remote_uploads_fail() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testPath = temporaryDirectory.appending(component: "test.framework")
        try await FileSystem().makeDirectory(at: testPath)

        let items = [CacheStorableItem(name: "target", hash: "hash"): [testPath]]
        let localResult = [CacheStorableItem(name: "target", hash: "hash")]
        let remoteResult: [CacheStorableItem] = [] // All remote uploads failed

        given(localStorage).store(.any, cacheCategory: .any).willReturn(localResult)
        given(remoteStorage).store(.any, cacheCategory: .any).willReturn(remoteResult)

        // When
        let result = try await subject.store(items, cacheCategory: .binaries)

        // Then
        #expect(result.isEmpty)
    }

    @Test(.inTemporaryDirectory)
    func store_propagates_local_storage_errors() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testPath = temporaryDirectory.appending(component: "test.framework")
        try await FileSystem().makeDirectory(at: testPath)

        let items = [CacheStorableItem(name: "target", hash: "hash"): [testPath]]
        let error = TestError("Local storage failed")

        given(localStorage).store(.any, cacheCategory: .any).willThrow(error)

        // When/Then
        await #expect(throws: TestError.self) {
            try await subject.store(items, cacheCategory: .binaries)
        }
    }

    @Test(.inTemporaryDirectory)
    func store_propagates_remote_storage_errors() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testPath = temporaryDirectory.appending(component: "test.framework")
        try await FileSystem().makeDirectory(at: testPath)

        let items = [CacheStorableItem(name: "target", hash: "hash"): [testPath]]
        let localResult = [CacheStorableItem(name: "target", hash: "hash")]
        let error = TestError("Remote storage failed")

        given(localStorage).store(.any, cacheCategory: .any).willReturn(localResult)
        given(remoteStorage).store(.any, cacheCategory: .any).willThrow(error)

        // When/Then
        await #expect(throws: TestError.self) {
            try await subject.store(items, cacheCategory: .binaries)
        }
    }

    @Test(.inTemporaryDirectory)
    func fetch_when_item_present_in_the_local_cache() async throws {
        // Given
        let cacheStorableItem = CacheStorableItem(name: "targetName", hash: "1234")
        let cacheItem: CacheItem = .test(name: "targetName", hash: "1234")
        let path: AbsolutePath = "/Absolute/Path"
        given(localStorage).fetch(
            .value(
                Set([
                    cacheStorableItem,
                ])
            ), cacheCategory: .value(.binaries)
        ).willReturn([
            cacheItem: path,
        ])
        given(remoteStorage).fetch(.value(Set([])), cacheCategory: .value(.binaries)).willReturn(
            [:]
        )

        // When
        let result = try await subject.fetch([cacheStorableItem], cacheCategory: .binaries)

        // Then
        #expect(result[cacheItem] == "/Absolute/Path")
    }

    @Test(.inTemporaryDirectory)
    func fetch_when_in_second_cache_checks_both_and_returns_path() async throws {
        // Given
        let cacheStorableItem = CacheStorableItem(name: "targetName", hash: "1234")
        let cacheItem: CacheItem = .test(name: "targetName", hash: "1234")
        let path: AbsolutePath = "/Absolute/Path"
        given(localStorage).fetch(
            .value(
                Set([
                    cacheStorableItem,
                ])
            ), cacheCategory: .value(.binaries)
        ).willReturn([:])
        given(remoteStorage).fetch(
            .value(
                Set([
                    cacheStorableItem,
                ])
            ), cacheCategory: .value(.binaries)
        ).willReturn([
            cacheItem: path,
        ])

        // When
        let result = try await subject.fetch([cacheStorableItem], cacheCategory: .binaries)

        // Then
        #expect(result[cacheItem] == "/Absolute/Path")
    }

    @Test(.inTemporaryDirectory)
    func fetch_when_item_absent_in_both_caches() async throws {
        // Given
        let cacheStorableItem = CacheStorableItem(name: "targetName", hash: "1234")
        let cacheItem: CacheItem = .test(name: "targetName", hash: "1234")
        given(localStorage).fetch(
            .value(
                Set([
                    cacheStorableItem,
                ])
            ), cacheCategory: .value(.binaries)
        ).willReturn([:])
        given(remoteStorage).fetch(
            .value(
                Set([
                    cacheStorableItem,
                ])
            ), cacheCategory: .value(.binaries)
        ).willReturn([:])

        // When
        let result = try await subject.fetch([cacheStorableItem], cacheCategory: .binaries)

        // Then
        #expect(result[cacheItem] == nil)
    }

    private struct TestError: Error, Equatable {
        let message: String

        init(_ message: String) {
            self.message = message
        }
    }
}
