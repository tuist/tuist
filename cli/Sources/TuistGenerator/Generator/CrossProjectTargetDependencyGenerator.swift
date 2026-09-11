import Foundation
import Path
import TuistCore
import XcodeGraph
import XcodeProj

/// Wires cross-project target dependencies and producer-linked product references.
///
/// Foreign build aggregates produce no product that Xcode can use for implicit dependency discovery.
/// Swift macro implementations need an explicit target edge so Xcode can discover and propagate their
/// native macro metadata.
///
/// Cross-project resource bundles need a `PBXReferenceProxy` instead of a standalone
/// `BUILT_PRODUCTS_DIR` file reference. A standalone reference only names a file the build products
/// directory is expected to contain, so SwiftBuild adds it as an additional CodeSign input only once
/// that file exists. On a fresh derived data directory the bundles are absent during the first Create
/// Build Description pass and present during the second, which changes the build description
/// signature and forces a replan that the inputs would not otherwise require. A proxy names the
/// producing project and target, so the bundle is a known output from the first pass on.
///
/// For each cross-project edge this generator adds the
/// following to the consumer's pbxproj:
///
/// - A `PBXFileReference` to the remote `.xcodeproj` (deduplicated per remote project).
/// - A `PBXProject.projects` entry pairing that reference with a Products `PBXGroup`.
/// - A `PBXContainerItemProxy` with `proxyType = .nativeTarget`,
///   `containerPortal = .fileReference(<remote .xcodeproj ref>)`, and
///   `remoteGlobalID = .object(<remote target>)`.
/// - A `PBXTargetDependency` wrapping the proxy, appended to the consumer target's `dependencies`.
/// - For resource bundles, a `PBXReferenceProxy` pointing at the remote target's product reference,
///   replacing the standalone `BUILT_PRODUCTS_DIR` file reference in consumer build phases.
///
/// XcodeProj's `ReferenceGenerator` assigns deterministic UUIDs lazily at encode time. The
/// consumer pbxproj serializes the proxy's `remoteGlobalIDString` from the remote target's
/// reference value, so we eagerly encode each dependency pbxproj once up front to fix its
/// UUIDs. When the writer later writes the consumer pbxproj, the proxy resolves to the
/// stable remote UUID instead of the temporary placeholder.
protocol CrossProjectTargetDependencyGenerating {
    func generate(
        graphTraverser: GraphTraversing,
        projectDescriptors: [ProjectDescriptor]
    ) throws
}

struct CrossProjectTargetDependencyGenerator: CrossProjectTargetDependencyGenerating {
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
        var productReferenceGenerator = CrossProjectProductReferenceGenerator()
        for edge in edges {
            wire(
                edge: edge,
                graphTraverser: graphTraverser,
                descriptorsByPath: descriptorsByPath,
                fileRefCache: &fileRefCache,
                productReferenceGenerator: &productReferenceGenerator
            )
        }
        productReferenceGenerator.removeOrphanedReferences()

        wireTransitiveProjectReferences(
            edges: edges,
            descriptorsByPath: descriptorsByPath,
            fileRefCache: &fileRefCache
        )
    }

    /// Whether a target dependency lands in another generated SPM package (external) project.
    /// Unlike `foreignBuild()` aggregates and macros, plain package-to-package dependencies (e.g. a
    /// package linking a product of another package) get no explicit edge from the checks above,
    /// even though each generated package becomes its own separate `.xcodeproj`. Without an edge here,
    /// Xcode's implicit dependency discovery is the only thing ordering the two package projects,
    /// which is only correct by accident (see the transitive-reference note below for the standalone
    /// `-project` build implications once this edge exists).
    private func isExternalPackageProject(_ graphTarget: GraphTarget) -> Bool {
        if case .external = graphTarget.project.type { return true }
        return false
    }

    /// `xcodebuild -project` (i.e. without a wrapping `.xcworkspace`) only discovers subprojects
    /// declared directly in the primary project's own `PBXProject.projectReferences` — it does not
    /// recurse into a nested subproject's own `projectReferences` to find further-nested projects.
    /// A consumer that depends on a package project which itself depends on another package
    /// project (e.g. an app linking `swift-nio`, which itself links `swift-atomics`) therefore
    /// never gets `swift-atomics.xcodeproj` opened/scheduled at all when built as a standalone
    /// project, even though the target-dependency graph between `swift-nio` and `swift-atomics` is
    /// entirely correct — confirmed via a plain `xcodebuild -project` build never scheduling the
    /// second-hop package's targets at all, while the same build succeeds through the generated
    /// `.xcworkspace`, which lists every package project as a flat top-level member.
    ///
    /// To make standalone `-project` builds work the same way, every project's
    /// `PBXProject.projectReferences` is expanded to the full transitive closure of package
    /// projects reachable from it, not just its direct one-hop dependencies. No additional
    /// `PBXTargetDependency` is added here: the real build-order edge already exists at whichever
    /// level the actual target dependency lives (wired above by `wire(edge:...)`); this only adds
    /// the file-reference "visibility" Xcode needs to discover and open the project at all.
    private func wireTransitiveProjectReferences(
        edges: [Edge],
        descriptorsByPath: [AbsolutePath: ProjectDescriptor],
        fileRefCache: inout [FileRefKey: PBXFileReference]
    ) {
        var adjacency: [AbsolutePath: Set<AbsolutePath>] = [:]
        for edge in edges {
            adjacency[edge.consumerProjectPath, default: []].insert(edge.dependencyProjectPath)
        }

        for consumerPath in adjacency.keys.sorted() {
            let directNeighbors = adjacency[consumerPath] ?? []
            let closure = transitiveClosure(from: consumerPath, adjacency: adjacency)
            let indirectDependencyPaths = closure.subtracting(directNeighbors).subtracting([consumerPath])
            guard !indirectDependencyPaths.isEmpty else { continue }

            for dependencyPath in indirectDependencyPaths.sorted() {
                guard let consumerDescriptor = descriptorsByPath[consumerPath],
                      let dependencyDescriptor = descriptorsByPath[dependencyPath],
                      let consumerProject = consumerDescriptor.xcodeProj.pbxproj.projects.first
                else { continue }

                _ = remoteProjectFileReference(
                    consumerProject: consumerProject,
                    consumerPbxproj: consumerDescriptor.xcodeProj.pbxproj,
                    consumerXcodeprojDirectory: consumerDescriptor.xcodeprojPath.parentDirectory,
                    remoteXcodeprojPath: dependencyDescriptor.xcodeprojPath,
                    cacheKey: FileRefKey(
                        consumerProjectPath: consumerPath,
                        remoteXcodeprojPath: dependencyDescriptor.xcodeprojPath
                    ),
                    cache: &fileRefCache
                )
            }
        }
    }

    private func transitiveClosure(
        from start: AbsolutePath,
        adjacency: [AbsolutePath: Set<AbsolutePath>]
    ) -> Set<AbsolutePath> {
        var visited: Set<AbsolutePath> = []
        var stack = Array(adjacency[start] ?? [])
        while let next = stack.popLast() {
            guard !visited.contains(next) else { continue }
            visited.insert(next)
            stack.append(contentsOf: adjacency[next] ?? [])
        }
        return visited
    }

    private struct Edge: Hashable {
        let consumerProjectPath: AbsolutePath
        let consumerTargetName: String
        let dependencyProjectPath: AbsolutePath
        let dependencyTargetName: String
        let condition: PlatformCondition?
        let linksProductReference: Bool
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
                    guard reference.graphTarget.target.foreignBuild != nil
                        || reference.graphTarget.target.product == .macro
                        || isExternalPackageProject(reference.graphTarget)
                    else {
                        continue
                    }
                    edges.insert(Edge(
                        consumerProjectPath: consumerPath,
                        consumerTargetName: target.name,
                        dependencyProjectPath: reference.graphTarget.path,
                        dependencyTargetName: reference.graphTarget.target.name,
                        condition: reference.condition,
                        linksProductReference: false
                    ))
                }
                for reference in graphTraverser.resourceBundleTargetDependencies(path: consumerPath, name: target.name) {
                    guard reference.graphTarget.path != consumerPath else { continue }
                    edges.insert(Edge(
                        consumerProjectPath: consumerPath,
                        consumerTargetName: target.name,
                        dependencyProjectPath: reference.graphTarget.path,
                        dependencyTargetName: reference.graphTarget.target.name,
                        condition: reference.condition,
                        linksProductReference: true
                    ))
                }
            }
        }
        return edges.sorted { lhs, rhs in
            (
                lhs.consumerProjectPath,
                lhs.consumerTargetName,
                lhs.dependencyProjectPath,
                lhs.dependencyTargetName,
                lhs.linksProductReference ? 1 : 0
            ) < (
                rhs.consumerProjectPath,
                rhs.consumerTargetName,
                rhs.dependencyProjectPath,
                rhs.dependencyTargetName,
                rhs.linksProductReference ? 1 : 0
            )
        }
    }

    private func wire(
        edge: Edge,
        graphTraverser: GraphTraversing,
        descriptorsByPath: [AbsolutePath: ProjectDescriptor],
        fileRefCache: inout [FileRefKey: PBXFileReference],
        productReferenceGenerator: inout CrossProjectProductReferenceGenerator
    ) {
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
              let dependencyTarget = target(named: edge.dependencyTargetName, in: dependencyPbxproj)
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

        if edge.linksProductReference, let dependencyNativeTarget = dependencyTarget as? PBXNativeTarget {
            productReferenceGenerator.generate(
                consumerProjectPath: edge.consumerProjectPath,
                dependencyProjectPath: edge.dependencyProjectPath,
                dependencyTargetName: edge.dependencyTargetName,
                consumerProject: consumerProject,
                consumerTarget: consumerTarget,
                consumerPbxproj: consumerPbxproj,
                dependencyTarget: dependencyNativeTarget,
                remoteProjectRef: remoteProjectRef
            )
        }

        wireTargetDependency(
            edge: edge,
            consumerTarget: consumerTarget,
            consumerXcodeGraphTarget: consumerXcodeGraphTarget,
            consumerPbxproj: consumerPbxproj,
            dependencyTarget: dependencyTarget,
            remoteProjectRef: remoteProjectRef
        )
    }

    private func wireTargetDependency(
        edge: Edge,
        consumerTarget: PBXTarget,
        consumerXcodeGraphTarget: Target,
        consumerPbxproj: PBXProj,
        dependencyTarget: PBXTarget,
        remoteProjectRef: PBXFileReference
    ) {
        if consumerTarget.dependencies.contains(where: { dependency in
            guard let proxy = dependency.targetProxy else { return false }
            return proxy.remoteInfo == edge.dependencyTargetName
                && proxy.containerPortal == .fileReference(remoteProjectRef)
        }) {
            return
        }

        let proxy = PBXContainerItemProxy(
            containerPortal: .fileReference(remoteProjectRef),
            remoteGlobalID: .object(dependencyTarget),
            proxyType: .nativeTarget,
            remoteInfo: edge.dependencyTargetName
        )
        consumerPbxproj.add(object: proxy)

        let dependency = PBXTargetDependency(name: edge.dependencyTargetName, targetProxy: proxy)
        dependency.applyCondition(edge.condition, applicableTo: consumerXcodeGraphTarget)
        consumerPbxproj.add(object: dependency)
        consumerTarget.dependencies.append(dependency)
    }

    private func target(named name: String, in pbxproj: PBXProj) -> PBXTarget? {
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
