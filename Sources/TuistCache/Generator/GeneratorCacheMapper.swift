import Basic
import Foundation
import RxSwift
import TuistCore
import TuistSupport

/// It defines the interface to map a graph and swap those targets
/// that have an associated .xcframework in the cache. Note that transitive
/// dependencies should be cacheable too.
public protocol GeneratorCacheMapping {
    /// Given a graph, it modifies it to replace some of the nodes with their associated from the cache.
    /// Note that cache might be remote so we model the asynchrony by returning an observable instead.
    /// - Parameter graph: Graph.
    /// - Returns: A single to obtain the mutated graph.
    func map(graph: Graph) -> Single<Graph>
}

public class GeneratorCacheMapper: GeneratorCacheMapping {
    // MARK: - Attributes

    /// Cache.
    private let cache: CacheStoraging

    /// Graph content hasher.
    private let graphContentHasher: GraphContentHashing

    /// Cache graph mapper.
    private let cacheGraphMapper: CacheGraphMapping

    /// Dispatch queue.
    private let queue: DispatchQueue

    // MARK: - Init

    public convenience init() {
        self.init(cache: Cache(),
                  graphContentHasher: GraphContentHasher())
    }

    init(cache: CacheStoraging,
         graphContentHasher: GraphContentHashing,
         cacheGraphMapper: CacheGraphMapping = CacheGraphMapper(),
         queue: DispatchQueue = GeneratorCacheMapper.dispatchQueue()) {
        self.cache = cache
        self.graphContentHasher = graphContentHasher
        self.queue = queue
        self.cacheGraphMapper = cacheGraphMapper
    }

    // MARK: - CacheGraphMapping

    public func map(graph: Graph) -> Single<Graph> {
        hashes(graph: graph).flatMap { self.map(graph: graph, hashes: $0) }
    }

    // MARK: - Fileprivate

    fileprivate static func dispatchQueue() -> DispatchQueue {
        let qos: DispatchQoS = .userInitiated
        return DispatchQueue(label: "io.tuist.generator-cache-mapper.\(qos)", qos: qos, attributes: [], target: nil)
    }

    fileprivate func hashes(graph: Graph) -> Single<[TargetNode: String]> {
        Single.create { (observer) -> Disposable in
            do {
                let hashes = try self.graphContentHasher.contentHashes(for: graph)
                observer(.success(hashes))
            } catch {
                observer(.error(error))
            }
            return Disposables.create {}
        }
        .subscribeOn(ConcurrentDispatchQueueScheduler(queue: queue))
    }

    fileprivate func map(graph: Graph, hashes: [TargetNode: String]) -> Single<Graph> {
        fetch(hashes: hashes).map { xcframeworkPaths in
            try self.cacheGraphMapper.map(graph: graph, xcframeworks: xcframeworkPaths)
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
