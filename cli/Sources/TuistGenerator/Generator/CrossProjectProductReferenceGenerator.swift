import Foundation
import Path
import XcodeProj

/// Creates the `PBXReferenceProxy` that lets a consumer project reference a product built by another
/// project, and repoints the consumer's build files at it.
///
/// The project generator emits a standalone `PBXFileReference` with `sourceTree = BUILT_PRODUCTS_DIR`
/// for every product a target consumes, which names a file the build products directory is expected to
/// contain without saying which project and target produce it. A proxy pairs the product reference in
/// the producer `.xcodeproj` with a `PBXContainerItemProxy`, so the relationship survives into the
/// generated project instead of having to be rediscovered by matching file names.
///
/// Instances accumulate the references they replaced; call `removeOrphanedReferences` once every edge
/// has been wired to drop the ones nothing points at anymore.
struct CrossProjectProductReferenceGenerator {
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
