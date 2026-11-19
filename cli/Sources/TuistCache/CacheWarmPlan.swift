import Path
import TuistCore
import TuistServer
import XcodeGraph

/// Keeps each partial warm's source retention, dependency lookup, build destination and publication in one SDK.
public struct CacheWarmPlan {
    public let batches: [Batch]
    public let localHits: [[CacheStorableItem: AbsolutePath]]

    public struct Batch {
        public let variant: BinaryCacheVariant?
        public let targets: [(GraphTarget, String)]
        public let fingerprints: [String: [String: String]]
    }

    public static func make(
        targets: [(GraphTarget, String)],
        fingerprints: [String: [String: String]],
        sdkSelection: BinaryCacheSDKSelection = .all,
        generateOnly: Bool = false,
        useSDKs: Bool = true,
        storage: CacheStoring,
        preserving resolvedHashes: Set<String>
    ) async throws -> CacheWarmPlan {
        guard useSDKs, !generateOnly else {
            return CacheWarmPlan(
                batches: targets.isEmpty ? [] : [Batch(variant: nil, targets: targets, fingerprints: fingerprints)], localHits: []
            )
        }
        var batches: [Batch] = []
        var localHits: [[CacheStorableItem: AbsolutePath]] = []
        var foundSlice = false
        for variant in BinaryCacheVariant.allCases where sdkSelection.includes(variant) {
            let candidates = targets.filter { fingerprints[$0.1]?[variant.rawValue] != nil }
            guard !candidates.isEmpty else { continue }
            let requested = Set(candidates.map { target, hash in
                CacheStorableItem(name: target.target.name, hash: hash, metadata: .init(
                    binaryCacheFingerprints: [variant.rawValue: fingerprints[hash]![variant.rawValue]!],
                    requiresSDKSlices: true
                ))
            })
            let hits = try await storage.fetch(requested, cacheCategory: .binaries, preserving: resolvedHashes)
            foundSlice = foundSlice || !hits.isEmpty
            let localPaths = Dictionary(uniqueKeysWithValues: hits.filter { $0.key.source == .local }.map {
                (CacheStorableItem(name: $0.key.name, hash: $0.key.hash), $0.value)
            })
            localHits.append(Dictionary(uniqueKeysWithValues: requested.compactMap { item in
                localPaths[item].map { (item, $0) }
            }))
            let hitItems = Set(hits.keys.map { CacheStorableItem(name: $0.name, hash: $0.hash) })
            let missing = candidates.filter { target, hash in
                !hitItems.contains(CacheStorableItem(name: target.target.name, hash: hash))
            }
            if !missing.isEmpty {
                batches.append(Batch(variant: variant, targets: missing, fingerprints: fingerprints.mapValues {
                    $0.filter { $0.key == variant.rawValue }
                }))
            }
        }
        if sdkSelection == .all, !foundSlice {
            return CacheWarmPlan(
                batches: targets.isEmpty ? [] : [Batch(variant: nil, targets: targets, fingerprints: fingerprints)], localHits: []
            )
        }
        let exact = targets.filter { fingerprints[$0.1, default: [:]].isEmpty }
        if !exact.isEmpty {
            batches.insert(Batch(variant: nil, targets: exact, fingerprints: [:]), at: 0)
        }
        return CacheWarmPlan(batches: batches, localHits: localHits.filter { !$0.isEmpty })
    }
}
