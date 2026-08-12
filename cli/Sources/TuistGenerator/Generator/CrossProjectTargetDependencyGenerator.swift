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

private struct CrossProjectProductReferenceGenerator {
    private struct CacheKey: Hashable {
        let consumerProjectPath: AbsolutePath
        let dependencyProjectPath: AbsolutePath
        let dependencyTargetName: String
    }

    private var cache: [CacheKey: PBXReferenceProxy] = [:]
    private var replacedReferences: [ObjectIdentifier: (pbxproj: PBXProj, references: [PBXFileReference])] = [:]
    private var replacedReferenceIDs: Set<ObjectIdentifier> = []
    private var localProductIDsByProject: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]

    mutating func generate(
        consumerProjectPath: AbsolutePath,
        dependencyProjectPath: AbsolutePath,
        dependencyTargetName: String,
        consumerProject: PBXProject,
        consumerTarget: PBXTarget,
        consumerPbxproj: PBXProj,
        dependencyTarget: PBXNativeTarget,
        remoteProjectRef: PBXFileReference
    ) {
        guard let dependencyProduct = dependencyTarget.product else { return }
        let cacheKey = CacheKey(
            consumerProjectPath: consumerProjectPath,
            dependencyProjectPath: dependencyProjectPath,
            dependencyTargetName: dependencyTargetName
        )
        guard let productProxy = productProxy(
            cacheKey: cacheKey,
            dependencyTargetName: dependencyTargetName,
            dependencyProduct: dependencyProduct,
            consumerProject: consumerProject,
            consumerPbxproj: consumerPbxproj,
            remoteProjectRef: remoteProjectRef
        ) else { return }
        replaceStandaloneReferences(
            to: productProxy,
            dependencyProduct: dependencyProduct,
            consumerTarget: consumerTarget,
            consumerPbxproj: consumerPbxproj
        )
    }

    func removeOrphanedReferences() {
        for (pbxproj, references) in replacedReferences.values {
            let referencedByBuildFile = Set(pbxproj.buildFiles.compactMap { $0.file.map(ObjectIdentifier.init) })
            let orphans = Set(
                references.map(ObjectIdentifier.init).filter { !referencedByBuildFile.contains($0) }
            )
            guard !orphans.isEmpty else { continue }

            for group in pbxproj.groups {
                group.children.removeAll { orphans.contains(ObjectIdentifier($0)) }
            }
            for reference in references where orphans.contains(ObjectIdentifier(reference)) {
                pbxproj.delete(object: reference)
            }
        }
    }

    private mutating func productProxy(
        cacheKey: CacheKey,
        dependencyTargetName: String,
        dependencyProduct: PBXFileReference,
        consumerProject: PBXProject,
        consumerPbxproj: PBXProj,
        remoteProjectRef: PBXFileReference
    ) -> PBXReferenceProxy? {
        if let cached = cache[cacheKey] { return cached }

        guard let remoteProductsGroup = productsGroup(for: remoteProjectRef, in: consumerProject) else { return nil }
        if let existing = existingProxy(for: dependencyProduct, in: remoteProductsGroup) {
            cache[cacheKey] = existing
            return existing
        }

        let containerProxy = PBXContainerItemProxy(
            containerPortal: .fileReference(remoteProjectRef),
            remoteGlobalID: .object(dependencyProduct),
            proxyType: .reference,
            remoteInfo: dependencyTargetName
        )
        consumerPbxproj.add(object: containerProxy)
        let productProxy = PBXReferenceProxy(
            fileType: dependencyProduct.explicitFileType ?? dependencyProduct.lastKnownFileType,
            path: dependencyProduct.path,
            name: dependencyProduct.name,
            remote: containerProxy,
            sourceTree: .buildProductsDir
        )
        consumerPbxproj.add(object: productProxy)
        remoteProductsGroup.children.append(productProxy)
        cache[cacheKey] = productProxy
        return productProxy
    }

    private func existingProxy(for product: PBXFileReference, in group: PBXGroup) -> PBXReferenceProxy? {
        group.children.compactMap { $0 as? PBXReferenceProxy }.first(where: {
            guard $0.path == product.path,
                  let remote = $0.remote,
                  case let .object(remoteProduct) = remote.remoteGlobalID
            else { return false }
            return remoteProduct === product
        })
    }

    /// Points the consumer's build files at the producer-linked proxy instead of the standalone
    /// `BUILT_PRODUCTS_DIR` reference the project generator emitted for the same product name.
    ///
    /// A target in the consumer project can produce a product with that same name, in which case its
    /// own product reference must stay untouched.
    private mutating func replaceStandaloneReferences(
        to productProxy: PBXReferenceProxy,
        dependencyProduct: PBXFileReference,
        consumerTarget: PBXTarget,
        consumerPbxproj: PBXProj
    ) {
        let localProducts = localProductIDs(in: consumerPbxproj)
        for buildFile in consumerTarget.buildPhases.flatMap({ $0.files ?? [] }) {
            guard let fileReference = buildFile.file as? PBXFileReference,
                  fileReference.sourceTree == .buildProductsDir,
                  fileReference.path == dependencyProduct.path,
                  !localProducts.contains(ObjectIdentifier(fileReference))
            else { continue }
            buildFile.file = productProxy
            guard replacedReferenceIDs.insert(ObjectIdentifier(fileReference)).inserted else { continue }
            replacedReferences[ObjectIdentifier(consumerPbxproj), default: (consumerPbxproj, [])]
                .references.append(fileReference)
        }
    }

    private mutating func localProductIDs(in pbxproj: PBXProj) -> Set<ObjectIdentifier> {
        let key = ObjectIdentifier(pbxproj)
        if let cached = localProductIDsByProject[key] { return cached }
        let ids = Set(pbxproj.nativeTargets.compactMap { $0.product.map(ObjectIdentifier.init) })
        localProductIDsByProject[key] = ids
        return ids
    }

    private func productsGroup(for remoteProjectRef: PBXFileReference, in project: PBXProject) -> PBXGroup? {
        project.projects.first(where: {
            $0[Xcode.ProjectReference.projectReferenceKey] as? PBXFileReference === remoteProjectRef
        })?[Xcode.ProjectReference.productGroupKey] as? PBXGroup
    }
}
