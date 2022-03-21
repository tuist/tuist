import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

enum FocusTargetsGraphMapperError: FatalError, Equatable {
    case missingTargets(missingTargets: [String], availableTargets: [String])

    var description: String {
        switch self {
        case let .missingTargets(missingTargets: missingTargets, availableTargets: availableTargets):
            return "Targets \(missingTargets.joined(separator: ", ")) cannot be found. Available targets are \(availableTargets.joined(separator: ", "))"
        }
    }

    var type: ErrorType {
        switch self {
        case .missingTargets:
            return .abort
        }
    }
}

public final class TargetsToCacheBinariesGraphMapper: GraphMapping {
    // MARK: - Attributes

    /// Cache storage provider.
    private let cacheStorageProvider: CacheStorageProviding

    /// Cache factory
    private let cacheFactory: CacheFactoring

    /// Graph content hasher.
    private let cacheGraphContentHasher: CacheGraphContentHashing

    /// Cache graph mapper.
    private let cacheGraphMutator: CacheGraphMutating

    /// Configuration object.
    private let config: Config

    /// List of targets that will be generated as sources instead of pre-compiled targets from the cache.
    private let sources: Set<String>

    /// The type of artifact that the hasher is configured with.
    private let cacheOutputType: CacheOutputType

    /// The caching profile.
    private let cacheProfile: TuistGraph.Cache.Profile

    // MARK: - Init

    public convenience init(
        config: Config,
        cacheStorageProvider: CacheStorageProviding,
        sources: Set<String>,
        cacheProfile: TuistGraph.Cache.Profile,
        cacheOutputType: CacheOutputType
    ) {
        self.init(
            config: config,
            cacheStorageProvider: cacheStorageProvider,
            cacheGraphContentHasher: CacheGraphContentHasher(),
            sources: sources,
            cacheProfile: cacheProfile,
            cacheOutputType: cacheOutputType
        )
    }

    init(
        config: Config,
        cacheStorageProvider: CacheStorageProviding,
        cacheFactory: CacheFactoring = CacheFactory(),
        cacheGraphContentHasher: CacheGraphContentHashing,
        sources: Set<String>,
        cacheProfile: TuistGraph.Cache.Profile,
        cacheOutputType: CacheOutputType,
        cacheGraphMutator: CacheGraphMutating = CacheGraphMutator()
    ) {
        self.config = config
        self.cacheStorageProvider = cacheStorageProvider
        self.cacheFactory = cacheFactory
        self.cacheGraphContentHasher = cacheGraphContentHasher
        self.cacheGraphMutator = cacheGraphMutator
        self.sources = sources
        self.cacheProfile = cacheProfile
        self.cacheOutputType = cacheOutputType
    }

    // MARK: - GraphMapping

    public func map(graph: Graph) async throws -> (Graph, [SideEffectDescriptor]) {
        let graphTraverser = GraphTraverser(graph: graph)
        let availableTargets = Set(
            graphTraverser.allTargets().map(\.target.name)
        )
        let allInternalTargets = Set(
            graphTraverser.allInternalTargets().map(\.target.name)
        )
        let sources = sources.isEmpty ? Set(allInternalTargets) : sources
        let missingTargets = sources.subtracting(availableTargets)
        guard missingTargets.isEmpty else {
            throw FocusTargetsGraphMapperError.missingTargets(
                missingTargets: missingTargets.sorted(),
                availableTargets: availableTargets.sorted()
            )
        }
        let hashes = try cacheGraphContentHasher.contentHashes(
            for: graph,
            cacheProfile: cacheProfile,
            cacheOutputType: cacheOutputType,
            excludedTargets: sources
        )
        let result = try cacheGraphMutator.map(
            graph: graph,
            precompiledArtifacts: await fetch(hashes: hashes),
            sources: sources
        )
        return (result, [])
    }

    // MARK: - Helpers

    private func fetch(hashes: [GraphTarget: String]) async throws -> [GraphTarget: AbsolutePath] {
        let storages = try cacheStorageProvider.storages()
        let cache = cacheFactory.cache(storages: storages)
        return try await hashes.concurrentMap { target, hash -> (GraphTarget, AbsolutePath?) in
            if try await cache.exists(name: target.target.name, hash: hash) {
                let path = try await cache.fetch(name: target.target.name, hash: hash)
                return (target, path)
            } else {
                return (target, nil)
            }
        }.reduce(into: [GraphTarget: AbsolutePath]()) { acc, next in
            guard let path = next.1 else { return }
            acc[next.0] = path
        }
    }
}
