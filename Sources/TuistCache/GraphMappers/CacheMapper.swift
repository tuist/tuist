import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistCore
import TuistSupport

public class CacheMapper: GraphMapping {
    // MARK: - Attributes

    /// Cache.
    private let cache: CacheStoring

    /// Graph content hasher.
    private let graphContentHasher: GraphContentHashing

    /// Cache graph mapper.
    private let cacheGraphMutator: CacheGraphMutating

    /// Configuration object.
    private let config: Config

    /// List of targets that will be generated as sources instead of pre-compiled targets from the cache.
    private let sources: Set<String>

    /// Dispatch queue.
    private let queue: DispatchQueue

    /// The type of artifact that the hasher is configured with.
    private let artifactType: ArtifactType

    // MARK: - Init

    public convenience init(config: Config,
                            cacheStorageProvider: CacheStorageProviding,
                            sources: Set<String>,
                            artifactType: ArtifactType)
    {
        self.init(config: config,
                  cache: Cache(storageProvider: cacheStorageProvider),
                  graphContentHasher: GraphContentHasher(),
                  sources: sources,
                  artifactType: artifactType)
    }

    init(config: Config,
         cache: CacheStoring,
         graphContentHasher: GraphContentHashing,
         sources: Set<String>,
         artifactType: ArtifactType,
         cacheGraphMutator: CacheGraphMutating = CacheGraphMutator(),
         queue: DispatchQueue = CacheMapper.dispatchQueue())
    {
        self.config = config
        self.cache = cache
        self.graphContentHasher = graphContentHasher
        self.queue = queue
        self.cacheGraphMutator = cacheGraphMutator
        self.sources = sources
        self.artifactType = artifactType
    }

    // MARK: - GraphMapping

    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        let single = hashes(graph: graph).flatMap { self.map(graph: graph, hashes: $0, sources: self.sources) }
        return try (single.toBlocking().single(), [])
    }

    // MARK: - Fileprivate

    fileprivate static func dispatchQueue() -> DispatchQueue {
        let qos: DispatchQoS = .userInitiated
        return DispatchQueue(label: "io.tuist.generator-cache-mapper.\(qos)", qos: qos, attributes: [], target: nil)
    }

    fileprivate func hashes(graph: Graph) -> Single<[TargetNode: String]> {
        Single.create { (observer) -> Disposable in
            do {
                let hashes = try self.graphContentHasher.contentHashes(for: graph,
                                                                       artifactType: self.artifactType)
                observer(.success(hashes))
            } catch {
                observer(.error(error))
            }
            return Disposables.create {}
        }
        .subscribeOn(ConcurrentDispatchQueueScheduler(queue: queue))
    }

    fileprivate func map(graph: Graph, hashes: [TargetNode: String], sources: Set<String>) -> Single<Graph> {
        fetch(hashes: hashes).map { xcframeworkPaths in
            try self.cacheGraphMutator.map(graph: graph,
                                           precompiledFrameworks: xcframeworkPaths,
                                           sources: sources)
        }
    }

    fileprivate func fetch(hashes: [TargetNode: String]) -> Single<[TargetNode: AbsolutePath]> {
        Single.zip(hashes.map { target, hash in
            self.cache.exists(hash: hash)
                .flatMap { (exists) -> Single<(target: TargetNode, path: AbsolutePath?)> in
                    guard exists else { return Single.just((target: target, path: nil)) }
                    return self.cache.fetch(hash: hash).map { (target: target, path: $0) }
                }
        })
            .map { result in
                result.reduce(into: [TargetNode: AbsolutePath]()) { acc, next in
                    guard let path = next.path else { return }
                    acc[next.target] = path
                }
            }
    }
}
