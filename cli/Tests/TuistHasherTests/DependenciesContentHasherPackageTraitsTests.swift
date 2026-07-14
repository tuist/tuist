import Mockable
import Path
import Testing
import TuistCore
import XcodeGraph

@testable import TuistHasher

struct DependenciesContentHasherPackageTraitsTests {
    @Test func hashChangesWhenPackageTraitsChange() async throws {
        let filePath = try AbsolutePath(validating: "/file1")
        let package = Package.local(path: filePath)
        let dependency = TargetDependency.package(product: "foo", type: .runtime)
        let firstGraphTarget = GraphTarget.test(
            target: Target.test(dependencies: [dependency]),
            project: Project.test(
                packages: [package],
                packageTraits: [.init(package: package, traits: ["FeatureA"])]
            )
        )
        let secondGraphTarget = GraphTarget.test(
            target: Target.test(dependencies: [dependency]),
            project: Project.test(
                packages: [package],
                packageTraits: [.init(package: package, traits: ["FeatureB"])]
            )
        )
        let subject = makeSubject()

        let firstHash = try await subject.hash(
            graphTarget: firstGraphTarget,
            hashedTargets: [:],
            hashedPaths: [:]
        ).hash
        let secondHash = try await subject.hash(
            graphTarget: secondGraphTarget,
            hashedTargets: [:],
            hashedPaths: [:]
        ).hash

        #expect(firstHash != secondHash)
    }

    @Test func hashDoesNotChangeWhenPackageTraitsAreReordered() async throws {
        let firstPackage = Package.local(path: try AbsolutePath(validating: "/file1"))
        let secondPackage = Package.local(path: try AbsolutePath(validating: "/file2"))
        let dependency = TargetDependency.package(product: "foo", type: .runtime)
        let firstGraphTarget = GraphTarget.test(
            target: Target.test(dependencies: [dependency]),
            project: Project.test(
                packages: [firstPackage, secondPackage],
                packageTraits: [
                    .init(package: firstPackage, traits: ["FeatureA", "FeatureB"]),
                    .init(package: secondPackage, traits: ["FeatureC"]),
                ]
            )
        )
        let secondGraphTarget = GraphTarget.test(
            target: Target.test(dependencies: [dependency]),
            project: Project.test(
                packages: [firstPackage, secondPackage],
                packageTraits: [
                    .init(package: secondPackage, traits: ["FeatureC"]),
                    .init(package: firstPackage, traits: ["FeatureB", "FeatureA"]),
                ]
            )
        )
        let subject = makeSubject()

        let firstHash = try await subject.hash(
            graphTarget: firstGraphTarget,
            hashedTargets: [:],
            hashedPaths: [:]
        ).hash
        let secondHash = try await subject.hash(
            graphTarget: secondGraphTarget,
            hashedTargets: [:],
            hashedPaths: [:]
        ).hash

        #expect(firstHash == secondHash)
    }

    private func makeSubject() -> DependenciesContentHasher {
        let contentHasher = MockContentHashing()
        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 + "-hash" }
        return DependenciesContentHasher(contentHasher: contentHasher)
    }
}
