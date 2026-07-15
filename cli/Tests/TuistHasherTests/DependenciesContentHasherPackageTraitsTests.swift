import Mockable
import Path
import Testing
import TuistCore
import XcodeGraph

@testable import TuistHasher

struct DependenciesContentHasherPackageTraitsTests {
    @Test func hashChangesWhenPackageTraitsChange() async throws {
        let filePath = try AbsolutePath(validating: "/file1")
        let dependency = TargetDependency.package(product: "foo", package: "file1", type: .runtime)
        let firstGraphTarget = GraphTarget.test(
            target: Target.test(dependencies: [dependency]),
            project: Project.test(
                packages: [.local(path: filePath, traits: ["FeatureA"])]
            )
        )
        let secondGraphTarget = GraphTarget.test(
            target: Target.test(dependencies: [dependency]),
            project: Project.test(
                packages: [.local(path: filePath, traits: ["FeatureB"])]
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
        let firstPackagePath = try AbsolutePath(validating: "/file1")
        let secondPackagePath = try AbsolutePath(validating: "/file2")
        let dependency = TargetDependency.package(product: "foo", package: "file1", type: .runtime)
        let firstGraphTarget = GraphTarget.test(
            target: Target.test(dependencies: [dependency]),
            project: Project.test(
                packages: [
                    .local(path: firstPackagePath, traits: ["FeatureA", "FeatureB"]),
                    .local(path: secondPackagePath, traits: ["FeatureC"]),
                ]
            )
        )
        let secondGraphTarget = GraphTarget.test(
            target: Target.test(dependencies: [dependency]),
            project: Project.test(
                packages: [
                    .local(path: secondPackagePath, traits: ["FeatureC"]),
                    .local(path: firstPackagePath, traits: ["FeatureB", "FeatureA"]),
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

    @Test func hashDoesNotChangeWhenUnrelatedPackageTraitsChange() async throws {
        let firstPackagePath = try AbsolutePath(validating: "/file1")
        let secondPackagePath = try AbsolutePath(validating: "/file2")
        let dependency = TargetDependency.package(product: "foo", package: "file2", type: .runtime)
        let firstGraphTarget = GraphTarget.test(
            target: Target.test(dependencies: [dependency]),
            project: Project.test(
                packages: [
                    .local(path: firstPackagePath, traits: ["FeatureA"]),
                    .local(path: secondPackagePath, traits: ["FeatureB"]),
                ]
            )
        )
        let secondGraphTarget = GraphTarget.test(
            target: Target.test(dependencies: [dependency]),
            project: Project.test(
                packages: [
                    .local(path: firstPackagePath, traits: ["FeatureC"]),
                    .local(path: secondPackagePath, traits: ["FeatureB"]),
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

    @Test func legacyPackageDependencyConservativelyHashesAllExplicitTraits() async throws {
        let filePath = try AbsolutePath(validating: "/file1")
        let dependency = TargetDependency.package(product: "foo", type: .runtime)
        let firstGraphTarget = GraphTarget.test(
            target: Target.test(dependencies: [dependency]),
            project: Project.test(
                packages: [.local(path: filePath, traits: ["FeatureA"])]
            )
        )
        let secondGraphTarget = GraphTarget.test(
            target: Target.test(dependencies: [dependency]),
            project: Project.test(
                packages: [.local(path: filePath, traits: ["FeatureB"])]
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

    private func makeSubject() -> DependenciesContentHasher {
        let contentHasher = MockContentHashing()
        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 + "-hash" }
        return DependenciesContentHasher(contentHasher: contentHasher)
    }
}
