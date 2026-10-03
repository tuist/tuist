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
                    guard reference.graphTarget.target.foreignBuild != nil || reference.graphTarget.target.product == .macro
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
        remoteXcodeprojPath: AbsolutePath,
        cacheKey: FileRefKey,
        cache: inout [FileRefKey: PBXFileReference]
    ) -> PBXFileReference {
        if let cached = cache[cacheKey] { return cached }

        // Xcode's PIF conversion keys a referenced subproject's identity off the literal
        // PBXFileReference.path string, not the resolved absolute path on disk. A relative path is
        // computed against the referencing project's own directory, so the exact same physical
        // .xcodeproj gets a different `path` string depending on which project references it (e.g.
        // a local package project living next to its own Package.swift vs. an external package
        // project living in the shared derived-projects cache vs. the app project at the repo
        // root) — and Xcode treats each distinct string as a separate target instance, which
        // surfaces as "Multiple commands produce" once a build needs the same target through more
        // than one of those instances. Using the absolute path instead makes every consumer, no
        // matter its own location, reference the target with the identical string, so Xcode
        // resolves them to one instance. Since generated projects are never checked into version
        // control (they're regenerated per machine/CI run), an absolute path doesn't cost
        // portability the way it would in a hand-maintained, committed project file.
        let absolutePath = remoteXcodeprojPath.pathString
        if let existing = consumerProject.projects
            .compactMap({ $0[Xcode.ProjectReference.projectReferenceKey] as? PBXFileReference })
            .first(where: { $0.path == absolutePath })
        {
            cache[cacheKey] = existing
            return existing
        }

        let fileReference = PBXFileReference(
            sourceTree: .absolute,
            name: remoteXcodeprojPath.basename,
            lastKnownFileType: "wrapper.pb-project",
            path: absolutePath
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
