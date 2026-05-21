import Foundation
import Path
import TuistCore
import XcodeGraph
import XcodeProj

/// Wires cross-project `PBXTargetDependency` edges for consumers that depend on a
/// `foreignBuild()` aggregate located in another project.
///
/// `foreignBuild()` aggregates produce no product under `BUILT_PRODUCTS_DIR`, so Xcode's implicit
/// dependency discovery (which walks framework references and product paths) does not pick them
/// up across project boundaries. Without an explicit cross-project `PBXTargetDependency`, the
/// aggregate's build script is never invoked when the consumer is built, and the consumer keeps
/// linking the stale artifact even after the foreign sources change.
///
/// For each cross-project edge `(consumer -> foreign-build aggregate)` this generator adds the
/// following to the consumer's pbxproj:
///
/// - A `PBXFileReference` to the remote `.xcodeproj` (deduplicated per remote project).
/// - A `PBXProject.projects` entry pairing that reference with an (empty) Products `PBXGroup`.
/// - A `PBXContainerItemProxy` with `proxyType = .nativeTarget`,
///   `containerPortal = .fileReference(<remote .xcodeproj ref>)`, and
///   `remoteGlobalID = .object(<remote aggregate>)`.
/// - A `PBXTargetDependency` wrapping the proxy, appended to the consumer target's
///   `dependencies`.
///
/// XcodeProj's `ReferenceGenerator` assigns deterministic UUIDs lazily at encode time. The
/// consumer pbxproj serializes the proxy's `remoteGlobalIDString` from the remote target's
/// reference value, so we eagerly encode each aggregate-bearing pbxproj once up front to fix
/// its UUIDs. When the writer later writes the consumer pbxproj, the proxy resolves to the
/// stable remote UUID instead of the temporary placeholder.
protocol ForeignBuildCrossProjectDependencyGenerating {
    func generate(
        graphTraverser: GraphTraversing,
        projectDescriptors: [ProjectDescriptor]
    ) throws
}

struct ForeignBuildCrossProjectDependencyGenerator: ForeignBuildCrossProjectDependencyGenerating {
    func generate(
        graphTraverser: GraphTraversing,
        projectDescriptors: [ProjectDescriptor]
    ) throws {
        let descriptorsByPath = Dictionary(uniqueKeysWithValues: projectDescriptors.map { ($0.path, $0) })
        let edges = collectEdges(graphTraverser: graphTraverser)
        guard !edges.isEmpty else { return }

        let aggregateProjectPaths = Set(edges.map(\.aggregateProjectPath))
        for path in aggregateProjectPaths.sorted() {
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
        let aggregateProjectPath: AbsolutePath
        let aggregateTargetName: String
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
                    guard reference.graphTarget.target.foreignBuild != nil else { continue }
                    edges.insert(Edge(
                        consumerProjectPath: consumerPath,
                        consumerTargetName: target.name,
                        aggregateProjectPath: reference.graphTarget.path,
                        aggregateTargetName: reference.graphTarget.target.name,
                        condition: reference.condition
                    ))
                }
            }
        }
        return edges.sorted { lhs, rhs in
            (lhs.consumerProjectPath, lhs.consumerTargetName, lhs.aggregateProjectPath, lhs.aggregateTargetName)
                < (rhs.consumerProjectPath, rhs.consumerTargetName, rhs.aggregateProjectPath, rhs.aggregateTargetName)
        }
    }

    private func wire(
        edge: Edge,
        graphTraverser: GraphTraversing,
        descriptorsByPath: [AbsolutePath: ProjectDescriptor],
        fileRefCache: inout [FileRefKey: PBXFileReference]
    ) throws {
        guard let consumerDescriptor = descriptorsByPath[edge.consumerProjectPath],
              let aggregateDescriptor = descriptorsByPath[edge.aggregateProjectPath],
              let consumerXcodeGraphTarget = graphTraverser.target(
                  path: edge.consumerProjectPath,
                  name: edge.consumerTargetName
              )?.target
        else { return }

        let consumerPbxproj = consumerDescriptor.xcodeProj.pbxproj
        let aggregatePbxproj = aggregateDescriptor.xcodeProj.pbxproj

        guard let consumerProject = consumerPbxproj.projects.first,
              let consumerTarget = consumerPbxproj.nativeTargets
              .first(where: { $0.name == edge.consumerTargetName }),
              let aggregateTarget = aggregateTarget(named: edge.aggregateTargetName, in: aggregatePbxproj)
        else { return }

        let remoteProjectRef = remoteProjectFileReference(
            consumerProject: consumerProject,
            consumerPbxproj: consumerPbxproj,
            consumerXcodeprojDirectory: consumerDescriptor.xcodeprojPath.parentDirectory,
            remoteXcodeprojPath: aggregateDescriptor.xcodeprojPath,
            cacheKey: FileRefKey(
                consumerProjectPath: edge.consumerProjectPath,
                remoteXcodeprojPath: aggregateDescriptor.xcodeprojPath
            ),
            cache: &fileRefCache
        )

        if consumerTarget.dependencies.contains(where: { dependency in
            guard let proxy = dependency.targetProxy else { return false }
            return proxy.remoteInfo == edge.aggregateTargetName
                && proxy.containerPortal == .fileReference(remoteProjectRef)
        }) {
            return
        }

        let proxy = PBXContainerItemProxy(
            containerPortal: .fileReference(remoteProjectRef),
            remoteGlobalID: .object(aggregateTarget),
            proxyType: .nativeTarget,
            remoteInfo: edge.aggregateTargetName
        )
        consumerPbxproj.add(object: proxy)

        let dependency = PBXTargetDependency(name: edge.aggregateTargetName, targetProxy: proxy)
        dependency.applyCondition(edge.condition, applicableTo: consumerXcodeGraphTarget)
        consumerPbxproj.add(object: dependency)
        consumerTarget.dependencies.append(dependency)
    }

    private func aggregateTarget(named name: String, in pbxproj: PBXProj) -> PBXTarget? {
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
