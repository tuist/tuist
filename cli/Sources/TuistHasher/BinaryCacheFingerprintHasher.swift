import Foundation
import Path
import TuistCore
import XcodeGraph

/// Hashes each compilation independently of the platform requirements of unrelated consumers.
public struct BinaryCacheFingerprintHasher {
    private let contentHasher: ContentHashing

    public init(contentHasher: ContentHashing = CachedContentHasher()) {
        self.contentHasher = contentHasher
    }

    /// `targetHashes` must come from the same graph and configuration in the current hashing invocation.
    public func fingerprints(
        graph: Graph,
        targets: Set<GraphTarget>,
        additionalStrings: [String],
        targetHashes: [GraphTarget: TargetContentHash] = [:]
    ) async throws -> [GraphTarget: [String: String]] {
        let worker = Worker(
            graph: graph, targets: targets, additionalStrings: additionalStrings,
            contentHasher: contentHasher, targetHashes: targetHashes
        )
        var result: [GraphTarget: [String: String]] = [:]
        for target in targets
            where [.framework, .staticFramework, .staticLibrary, .dynamicLibrary].contains(target.target.product)
        {
            // Other platforms keep exact-hash lookup until their SDK/architecture coverage is modeled.
            guard target.target.destinations.allSatisfy({ [.iOS, .macOS].contains($0.platform) }) else { continue }
            let variants = BinaryCacheVariant.allCases
                .filter { variant in target.target.destinations.contains { $0.platformFilter == variant.platformFilter } }
            for variant in variants {
                if let hash = try await worker.hash(target: target, variant: variant) {
                    result[target, default: [:]][variant.rawValue] = hash
                }
            }
            if result[target]?.count != variants.count { result[target] = nil }
        }
        return result
    }
}

private final class Worker {
    struct Key: Hashable {
        let target: GraphHashedTarget
        let variant: BinaryCacheVariant
    }

    let traverser: GraphTraverser
    let targets: [GraphHashedTarget: GraphTarget]
    let additionalStrings: [String]
    let targetContentHasher: TargetContentHasher
    var sharedSubhashes: [GraphHashedTarget: TargetContentHashSubhashes] = [:]
    var hashes: [Key: String] = [:]
    var hashedPaths: [AbsolutePath: String] = [:]

    init(
        graph: Graph,
        targets: Set<GraphTarget>,
        additionalStrings: [String],
        contentHasher: ContentHashing,
        targetHashes: [GraphTarget: TargetContentHash]
    ) {
        targetContentHasher = TargetContentHasher(contentHasher: contentHasher)
        traverser = GraphTraverser(graph: graph)
        for (target, value) in targetHashes {
            sharedSubhashes[.init(projectPath: target.path, targetName: target.target.name)] = value.subhashes
            hashedPaths.merge(value.hashedPaths, uniquingKeysWith: { _, new in new })
        }
        self.targets = Dictionary(uniqueKeysWithValues: targets.map {
            (GraphHashedTarget(projectPath: $0.path, targetName: $0.target.name), $0)
        })
        self.additionalStrings = additionalStrings
    }

    func hash(target: GraphTarget, variant requestedVariant: BinaryCacheVariant) async throws -> String? {
        let variant: BinaryCacheVariant = target.target.product == .macro ? .macos : requestedVariant
        let key = Key(target: .init(projectPath: target.path, targetName: target.target.name), variant: variant)
        if let cached = hashes[key] { return cached }
        guard target.target.destinations.contains(where: { $0.platformFilter == variant.platformFilter }),
              supportsStandardArchitectures(target.project.settings),
              target.target.settings.map(supportsStandardArchitectures) ?? true
        else { return nil }
        var model = target.target
        model.destinations = model.destinations.filter { $0.platformFilter == variant.platformFilter }
        model.deploymentTargets = DeploymentTargets(
            iOS: variant.platform == .iOS ? model.deploymentTargets.iOS : nil,
            macOS: variant.platform == .macOS ? model.deploymentTargets.macOS : nil
        )
        model.dependencies = model.dependencies.filter {
            $0.condition?.platformFilters.contains(variant.platformFilter) ?? true
        }
        var dependencyHashes: [GraphHashedTarget: String] = [:]
        for dependency in model.dependencies {
            let reference: GraphHashedTarget
            switch dependency {
            case let .target(name, _, _): reference = .init(projectPath: target.path, targetName: name)
            case let .project(name, path, _, _): reference = .init(projectPath: path, targetName: name)
            default: continue
            }
            guard let dependencyTarget = targets[reference],
                  let hash = try await hash(target: dependencyTarget, variant: variant)
            else { return nil }
            dependencyHashes[reference] = hash
        }
        let deployment = model.deploymentTargets[variant.platform] ?? ""
        let graphTarget = GraphTarget(path: target.path, target: model, project: target.project)
        let strings = additionalStrings + ["xcframework-fingerprint-v1", variant.rawValue, deployment]
        let value: (hash: String, hashedPaths: [AbsolutePath: String])
        if let subhashes = sharedSubhashes[key.target] {
            value = try await targetContentHasher.fingerprint(
                for: graphTarget, reusing: subhashes, hashedTargets: dependencyHashes,
                hashedPaths: hashedPaths, additionalStrings: strings
            )
        } else {
            let fullHash = try await targetContentHasher.contentHash(
                for: graphTarget, hashedTargets: dependencyHashes, hashedPaths: hashedPaths,
                destination: nil, embeddedProductReferences: embeddedReferences(for: target), additionalStrings: strings
            )
            sharedSubhashes[key.target] = fullHash.subhashes
            value = (fullHash.hash, fullHash.hashedPaths)
        }
        hashedPaths.merge(value.hashedPaths, uniquingKeysWith: { _, new in new })
        hashes[key] = value.hash
        return value.hash
    }

    private func embeddedReferences(for target: GraphTarget) -> [String] {
        traverser.resourceBundleDependencies(path: target.path, name: target.target.name)
            .union(traverser.embeddableFrameworks(path: target.path, name: target.target.name))
            .map(\.hashIdentifier).sorted()
    }

    private func supportsStandardArchitectures(_ settings: Settings) -> Bool {
        let keys = Array(settings.base.keys) + Array(settings.baseDebug.keys)
            + settings.configurations.values.compactMap { $0 }.flatMap(\.settings.keys)
        return !keys.contains { key in
            ["ARCHS", "EXCLUDED_ARCHS", "VALID_ARCHS"].contains { key == $0 || key.hasPrefix($0 + "[") }
        }
    }
}
