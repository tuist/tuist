import Basic
import Foundation
import RxBlocking
import RxSwift
import TuistCore
import TuistSupport

public class CacheMapper: GraphMapping {
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
         queue: DispatchQueue = CacheMapper.dispatchQueue()) {
        self.cache = cache
        self.graphContentHasher = graphContentHasher
        self.queue = queue
        self.cacheGraphMapper = cacheGraphMapper
    }

    // MARK: - GraphMapping

    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        let single = hashes(graph: graph).flatMap { self.map(graph: graph, hashes: $0) }
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
