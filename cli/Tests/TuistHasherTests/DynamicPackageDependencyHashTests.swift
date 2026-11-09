import Path
import Testing
import TuistCore
import XcodeGraph
@testable import TuistHasher

struct DynamicPackageDependencyHashTests {
    @Test(arguments: [false, true])
    func linkageAndEmbeddingRolesHaveDistinctFingerprints(withTraits: Bool) async throws {
        let roles: [TargetDependency.PackageType] = [
            .runtime, .runtimeEmbedded, .runtimeDynamic, .runtimeDynamicEmbedded, .plugin, .macro,
        ]
        let project = Project.test(packageTraits: withTraits ? ["local-package": ["FeatureA"]] : nil)
        let cachedPaths: [AbsolutePath: String] = ["/previous.framework": "previous-hash"]
        let subject = DependenciesContentHasher(contentHasher: ContentHasher())
        var hashes = Set<String>()

        for role in roles {
            let graphTarget = GraphTarget.test(
                target: Target.test(dependencies: [.package(product: "ProductAlias", type: role)]),
                project: project
            )
            let result = try await subject.hash(graphTarget: graphTarget, hashedTargets: [:], hashedPaths: cachedPaths)
            hashes.insert(result.hash)
            #expect(result.hashedPaths == cachedPaths)
        }

        #expect(hashes.count == roles.count)
    }

    @Test(arguments: [false, true])
    func existingRolesKeepTheirFingerprints(withEmptyTraits: Bool) async throws {
        let fingerprints: [TargetDependency.PackageType: String] = [
            .runtime: "package-ProductAlias-runtime",
            .runtimeEmbedded: "package-ProductAlias-runtimeEmbedded",
            .plugin: "package-ProductAlias-plugin",
            .macro: "package-ProductAlias-macro",
        ]
        let project = Project.test(packageTraits: withEmptyTraits ? [:] : nil)
        let contentHasher = ContentHasher()
        let subject = DependenciesContentHasher(contentHasher: contentHasher)

        for (role, fingerprint) in fingerprints {
            let graphTarget = GraphTarget.test(
                target: Target.test(dependencies: [.package(product: "ProductAlias", type: role)]),
                project: project
            )
            let result = try await subject.hash(graphTarget: graphTarget, hashedTargets: [:], hashedPaths: [:])

            let expectedHash = try contentHasher.hash(contentHasher.hash(fingerprint))
            #expect(result.hash == expectedHash)
        }
    }
}
