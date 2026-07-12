import Foundation
import Path
import TuistCore
import XcodeGraph
import XcodeProj

/// Wires explicit cross-project `PBXTargetDependency` edges for consumers that depend on a target
/// located in another generated project.
///
/// `TargetGenerator` only emits `PBXTargetDependency` for dependencies within the same project
/// (`directLocalTargetDependencies`). Cross-project dependencies are otherwise left to Xcode's
/// implicit dependency discovery (product-name matching across the shared build products dir),
/// which gives `swift-build` / `llbuild` no explicit ordering constraint. That ordering is then
/// only correct by accident: on a warm compilation-cache build replayed tasks finish near-instantly
/// and a downstream target's dependency scan can run before the upstream `.swiftmodule` exists,
/// surfacing as `unable to resolve module dependency`.
///
/// This generator closes that gap for two cases:
///
/// - Each generated SPM package becomes its own external project, so a target that links a product
///   of another package project needs an explicit edge across the package-project boundary.
/// - `foreignBuild()` aggregates produce no product under `BUILT_PRODUCTS_DIR`, so Xcode's implicit
///   discovery (which walks framework references and product paths) does not pick them up across
///   project boundaries at all. Without the explicit edge the aggregate's build script is never
///   invoked when the consumer builds, and the consumer keeps linking the stale artifact.
///
/// Cross-project edges between hand-written local projects are intentionally left to implicit
/// resolution to preserve existing behavior.
///
/// For each cross-project edge `(consumer -> dependency)` this generator adds the following to the
/// consumer's pbxproj:
///
/// - A `PBXFileReference` to the remote `.xcodeproj` (deduplicated per remote project).
/// - A `PBXProject.projects` entry pairing that reference with an (empty) Products `PBXGroup`.
/// - A `PBXContainerItemProxy` with `proxyType = .nativeTarget`,
///   `containerPortal = .fileReference(<remote .xcodeproj ref>)`, and
///   `remoteGlobalID = .object(<remote target>)`.
/// - A `PBXTargetDependency` wrapping the proxy, appended to the consumer target's
///   `dependencies`.
///
/// XcodeProj's `ReferenceGenerator` assigns deterministic UUIDs lazily at encode time. The
/// consumer pbxproj serializes the proxy's `remoteGlobalIDString` from the remote target's
/// reference value, so we eagerly encode each dependency-bearing pbxproj once up front to fix
/// its UUIDs. When the writer later writes the consumer pbxproj, the proxy resolves to the
/// stable remote UUID instead of the temporary placeholder.
protocol CrossProjectDependencyGenerating {
    func generate(
        graphTraverser: GraphTraversing,
        projectDescriptors: [ProjectDescriptor]
    ) throws
}

struct CrossProjectDependencyGenerator: CrossProjectDependencyGenerating {
    func generate(
        graphTraverser: GraphTraversing,
        projectDescriptors: [ProjectDescriptor]
    ) throws {
        let descriptorsByPath = Dictionary(uniqueKeysWithValues: projectDescriptors.map { ($0.path, $0) })
        let edges = collectEdges(graphTraverser: graphTraverser)
        guard !edges.isEmpty else { return }

        let dependencyProjectPaths = Set(edges.map(\.dependencyProjectPath))
        for path in dependencyProjectPaths.sorted() {
            guard let descriptor = descriptorsByPath[path] else { continue }
            _ = try descriptor.xcodeProj.pbxproj.dataRepresentation(outputSettings: PBXOutputSettings())
        }

        var fileRefCache: [FileRefKey: PBXFileReference] = [:]
        for edge in edges {
            try wire(
                edge: edge,
                graphTraverser: graphTraverser,
                descriptorsByPath: descriptorsByPath,
                fileRefCache: &fileRefCache
            )
        }
    }

    private struct Edge: Hashable {
        let consumerProjectPath: AbsolutePath
        let consumerTargetName: String
        let dependencyProjectPath: AbsolutePath
        let dependencyTargetName: String
        let condition: PlatformCondition?
    }

    private struct FileRefKey: Hashable {
        let consumerProjectPath: AbsolutePath
        let remoteXcodeprojPath: AbsolutePath
    }

    private func collectEdges(graphTraverser: GraphTraversing) -> [Edge] {
        var edges = Set<Edge>()
        for (consumerPath, project) in graphTraverser.projects {
            for (_, target) in project.targets {
                guard target.foreignBuild == nil else { continue }
                for reference in graphTraverser.directTargetDependencies(path: consumerPath, name: target.name) {
                    guard reference.graphTarget.path != consumerPath else { continue }
                    guard shouldWireCrossProjectDependency(to: reference.graphTarget) else { continue }
                    edges.insert(Edge(
                        consumerProjectPath: consumerPath,
                        consumerTargetName: target.name,
                        dependencyProjectPath: reference.graphTarget.path,
                        dependencyTargetName: reference.graphTarget.target.name,
                        condition: reference.condition
                    ))
                }
            }
        }
        return edges.sorted { lhs, rhs in
            (lhs.consumerProjectPath, lhs.consumerTargetName, lhs.dependencyProjectPath, lhs.dependencyTargetName)
                < (rhs.consumerProjectPath, rhs.consumerTargetName, rhs.dependencyProjectPath, rhs.dependencyTargetName)
        }
    }

    /// Whether a cross-project dependency on the given target should be wired explicitly. We only
    /// wire dependencies on generated SPM package projects (external) and `foreignBuild()`
    /// aggregates; cross-project edges between hand-written local projects keep relying on Xcode's
    /// implicit dependency resolution.
    private func shouldWireCrossProjectDependency(to graphTarget: GraphTarget) -> Bool {
        if graphTarget.target.foreignBuild != nil { return true }
        if case .external = graphTarget.project.type { return true }
        return false
    }

    private func wire(
        edge: Edge,
        graphTraverser: GraphTraversing,
        descriptorsByPath: [AbsolutePath: ProjectDescriptor],
        fileRefCache: inout [FileRefKey: PBXFileReference]
    ) throws {
        guard let consumerDescriptor = descriptorsByPath[edge.consumerProjectPath],
              let dependencyDescriptor = descriptorsByPath[edge.dependencyProjectPath],
              let consumerXcodeGraphTarget = graphTraverser.target(
                  path: edge.consumerProjectPath,
                  name: edge.consumerTargetName
              )?.target
        else { return }

        let consumerPbxproj = consumerDescriptor.xcodeProj.pbxproj
        let dependencyPbxproj = dependencyDescriptor.xcodeProj.pbxproj

        guard let consumerProject = consumerPbxproj.projects.first,
              let consumerTarget = consumerPbxproj.nativeTargets
              .first(where: { $0.name == edge.consumerTargetName }),
              let remoteTarget = remoteTarget(named: edge.dependencyTargetName, in: dependencyPbxproj)
        else { return }

        let remoteProjectRef = remoteProjectFileReference(
            consumerProject: consumerProject,
            consumerPbxproj: consumerPbxproj,
            consumerXcodeprojDirectory: consumerDescriptor.xcodeprojPath.parentDirectory,
            remoteXcodeprojPath: dependencyDescriptor.xcodeprojPath,
            cacheKey: FileRefKey(
                consumerProjectPath: edge.consumerProjectPath,
                remoteXcodeprojPath: dependencyDescriptor.xcodeprojPath
            ),
            cache: &fileRefCache
        )

        if consumerTarget.dependencies.contains(where: { dependency in
            guard let proxy = dependency.targetProxy else { return false }
            return proxy.remoteInfo == edge.dependencyTargetName
                && proxy.containerPortal == .fileReference(remoteProjectRef)
        }) {
            return
        }

        let proxy = PBXContainerItemProxy(
            containerPortal: .fileReference(remoteProjectRef),
            remoteGlobalID: .object(remoteTarget),
            proxyType: .nativeTarget,
            remoteInfo: edge.dependencyTargetName
        )
        consumerPbxproj.add(object: proxy)

        let dependency = PBXTargetDependency(name: edge.dependencyTargetName, targetProxy: proxy)
        dependency.applyCondition(edge.condition, applicableTo: consumerXcodeGraphTarget)
        consumerPbxproj.add(object: dependency)
        consumerTarget.dependencies.append(dependency)
    }

    private func remoteTarget(named name: String, in pbxproj: PBXProj) -> PBXTarget? {
        if let native = pbxproj.nativeTargets.first(where: { $0.name == name }) {
            return native
        }
        return pbxproj.aggregateTargets.first(where: { $0.name == name })
    }

    private func remoteProjectFileReference(
        consumerProject: PBXProject,
        consumerPbxproj: PBXProj,
        consumerXcodeprojDirectory: AbsolutePath,
        remoteXcodeprojPath: AbsolutePath,
        cacheKey: FileRefKey,
        cache: inout [FileRefKey: PBXFileReference]
    ) -> PBXFileReference {
        if let cached = cache[cacheKey] { return cached }

        let relativePath = remoteXcodeprojPath.relative(to: consumerXcodeprojDirectory).pathString
        if let existing = consumerProject.projects
            .compactMap({ $0[Xcode.ProjectReference.projectReferenceKey] as? PBXFileReference })
            .first(where: { $0.path == relativePath })
        {
            cache[cacheKey] = existing
            return existing
        }

        let fileReference = PBXFileReference(
            sourceTree: .group,
            name: remoteXcodeprojPath.basename,
            lastKnownFileType: "wrapper.pb-project",
            path: relativePath
        )
        consumerPbxproj.add(object: fileReference)
        consumerProject.mainGroup.children.append(fileReference)

        let productsGroup = PBXGroup(
            children: [],
            sourceTree: .group,
            name: "Products"
        )
        consumerPbxproj.add(object: productsGroup)

        consumerProject.projects.append([
            Xcode.ProjectReference.projectReferenceKey: fileReference,
            Xcode.ProjectReference.productGroupKey: productsGroup,
        ])

        cache[cacheKey] = fileReference
        return fileReference
    }
}
