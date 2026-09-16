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

    public func fingerprints(
        graph: Graph,
        targets: Set<GraphTarget>,
        additionalStrings: [String]
    ) async throws -> [GraphTarget: [String: String]] {
        let worker = Worker(graph: graph, targets: targets, additionalStrings: additionalStrings, contentHasher: contentHasher)
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

    let graph: Graph
    let targets: [GraphHashedTarget: GraphTarget]
    let additionalStrings: [String]
    let contentHasher: ContentHashing
    var hashes: [Key: String] = [:]
    var hashedPaths: [AbsolutePath: String] = [:]

    init(graph: Graph, targets: Set<GraphTarget>, additionalStrings: [String], contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
        self.graph = graph
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
        let traverser = GraphTraverser(graph: graph)
        let embeddedReferences = traverser.resourceBundleDependencies(path: target.path, name: target.target.name)
            .union(traverser.embeddableFrameworks(path: target.path, name: target.target.name))
            .map(\.hashIdentifier).sorted()
        let deployment = model.deploymentTargets[variant.platform] ?? ""
        let value = try await TargetContentHasher(contentHasher: contentHasher).contentHash(
            for: GraphTarget(path: target.path, target: model, project: target.project),
            hashedTargets: dependencyHashes,
            hashedPaths: hashedPaths,
            destination: nil,
            embeddedProductReferences: embeddedReferences,
            additionalStrings: additionalStrings + ["xcframework-fingerprint-v1", variant.rawValue, deployment]
        )
        hashedPaths.merge(value.hashedPaths, uniquingKeysWith: { _, new in new })
        hashes[key] = value.hash
        return value.hash
    }

    private func supportsStandardArchitectures(_ settings: Settings) -> Bool {
        let keys = Array(settings.base.keys) + Array(settings.baseDebug.keys)
            + settings.configurations.values.compactMap { $0 }.flatMap(\.settings.keys)
        return !keys.contains { key in
            ["ARCHS", "EXCLUDED_ARCHS", "VALID_ARCHS"].contains { key == $0 || key.hasPrefix($0 + "[") }
        }
    }
}
