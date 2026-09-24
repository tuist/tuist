#if canImport(TuistCore)
    import Foundation
    import Mockable
    import Path
    import TuistCore
    import XcodeGraph

    public struct CacheStorableTarget: Hashable, Equatable {
        public let target: GraphTarget
        public let hash: String
        public let metadata: CacheStorableItemMetadata
        public var name: String { target.target.name }

        public init(target: GraphTarget, hash: String, metadata: CacheStorableItemMetadata = .init()) {
            self.target = target
            self.hash = hash
            self.metadata = metadata
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(hash)
            hasher.combine(name)
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            return lhs.hash == rhs.hash && lhs.name == rhs.name
        }
    }

    public struct CacheStorableItem: Hashable, Equatable {
        public let name: String
        public let hash: String
        public let metadata: CacheStorableItemMetadata

        public init(name: String, hash: String, metadata: CacheStorableItemMetadata = CacheStorableItemMetadata()) {
            self.name = name
            self.hash = hash
            self.metadata = metadata
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(hash)
            hasher.combine(name)
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            return lhs.hash == rhs.hash && lhs.name == rhs.name
        }
    }

    public struct CacheStorableItemMetadata: Hashable, Equatable, Codable {
        public var binaryCacheFingerprints: [String: String]

        public init(binaryCacheFingerprints: [String: String] = [:]) {
            self.binaryCacheFingerprints = binaryCacheFingerprints
        }

        private enum CodingKeys: String, CodingKey { case binaryCacheFingerprints }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            binaryCacheFingerprints = try container
                .decodeIfPresent([String: String].self, forKey: .binaryCacheFingerprints) ?? [:]
        }
    }

    public struct CacheUploadFailure: Hashable, Equatable {
        public let item: CacheStorableItem
        public let reason: String

        public init(item: CacheStorableItem, reason: String) {
            self.item = item
            self.reason = reason
        }
    }

    /// Every item that is not among `failures` was uploaded.
    public struct CacheUploadError: LocalizedError, Equatable {
        public let failures: [CacheUploadFailure]

        public init(failures: [CacheUploadFailure]) {
            self.failures = failures
        }

        public var errorDescription: String? {
            let failures = failures
                .sorted { $0.item.name < $1.item.name }
                .map { "\($0.item.name) with hash \($0.item.hash): \($0.reason)" }
                .joined(separator: ", ")
            return "Failed to upload to the remote cache: \(failures)"
        }
    }

    @Mockable
    public protocol CacheStoring {
        func fetch(
            _ items: Set<CacheStorableItem>,
            cacheCategory: RemoteCacheCategory
        ) async throws -> [CacheItem: AbsolutePath]
        /// Entries for `resolvedHashes` have already been handed to the caller, so a storage that
        /// evicts to make room for what it fetches must not reclaim them.
        func fetch(
            _ items: Set<CacheStorableItem>,
            cacheCategory: RemoteCacheCategory,
            preserving resolvedHashes: Set<String>
        ) async throws -> [CacheItem: AbsolutePath]
        /// A remote storage attempts every item and then throws `CacheUploadError` if any of them failed to upload.
        func store(
            _ items: [CacheStorableItem: [AbsolutePath]],
            cacheCategory: RemoteCacheCategory
        ) async throws -> [CacheStorableItem]
    }

    extension CacheStoring {
        /// A storage that never evicts has nothing to preserve.
        public func fetch(
            _ items: Set<CacheStorableItem>,
            cacheCategory: RemoteCacheCategory,
            preserving _: Set<String>
        ) async throws -> [CacheItem: AbsolutePath] {
            try await fetch(items, cacheCategory: cacheCategory)
        }

        public func fetch(
            _ targets: Set<CacheStorableTarget>,
            cacheCategory: RemoteCacheCategory
        ) async throws -> [CacheStorableTarget: AbsolutePath] {
            Dictionary(
                uniqueKeysWithValues: try await fetch(
                    Set(targets.map { CacheStorableItem(name: $0.name, hash: $0.hash, metadata: $0.metadata) }),
                    cacheCategory: cacheCategory
                )
                .compactMap { item, path -> (CacheStorableTarget, AbsolutePath)? in
                    guard let target = targets.first(where: { $0.hash == item.hash }) else {
                        return nil
                    }
                    return (target, path)
                }
            )
        }

        public func store(
            _ targets: [CacheStorableTarget: [AbsolutePath]],
            cacheCategory: RemoteCacheCategory
        ) async throws -> [CacheStorableTarget] {
            let items = Dictionary(
                uniqueKeysWithValues: targets.map { target, paths -> (CacheStorableItem, [AbsolutePath]) in
                    (
                        CacheStorableItem(
                            name: target.name,
                            hash: target.hash,
                            metadata: target.metadata
                        ),
                        paths
                    )
                }
            )
            let successfulItems = try await store(items, cacheCategory: cacheCategory)
            return successfulItems.compactMap { item in
                targets.first { $0.key.hash == item.hash && $0.key.name == item.name }?.key
            }
        }
    }
#endif
