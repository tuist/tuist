import Mockable
import Testing
import TuistCore
import XcodeGraph

@testable import TuistHasher

struct DependenciesContentHasherPackageTraitsTests {
    @Test func hashChangesWhenPackageTraitsChange() async throws {
        let dependency = TargetDependency.package(product: "foo", type: .runtime)
        let firstGraphTarget = GraphTarget.test(
            target: Target.test(dependencies: [dependency]),
            project: Project.test(packageTraits: ["package": ["FeatureA"]])
        )
        let secondGraphTarget = GraphTarget.test(
            target: Target.test(dependencies: [dependency]),
            project: Project.test(packageTraits: ["package": ["FeatureB"]])
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
        let dependency = TargetDependency.package(product: "foo", type: .runtime)
        let firstGraphTarget = GraphTarget.test(
            target: Target.test(dependencies: [dependency]),
            project: Project.test(
                packageTraits: [
                    "first": ["FeatureA", "FeatureB"],
                    "second": ["FeatureC"],
                ]
            )
        )
        let secondGraphTarget = GraphTarget.test(
            target: Target.test(dependencies: [dependency]),
            project: Project.test(
                packageTraits: [
                    "second": ["FeatureC"],
                    "first": ["FeatureB", "FeatureA"],
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

    @Test func structuredFingerprintDistinguishesHyphenatedProductAndPackageNames() async throws {
        let firstGraphTarget = GraphTarget.test(
            target: Target.test(dependencies: [.package(product: "foo-bar", type: .runtime)]),
            project: Project.test(packageTraits: ["baz": []])
        )
        let secondGraphTarget = GraphTarget.test(
            target: Target.test(dependencies: [.package(product: "foo", type: .runtime)]),
            project: Project.test(packageTraits: ["bar-baz": []])
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

    @Test func packagesWithoutExplicitTraitsKeepTheLegacyHash() async throws {
        let dependency = TargetDependency.package(product: "foo", type: .runtime)
        let graphTarget = GraphTarget.test(
            target: Target.test(dependencies: [dependency]),
            project: Project.test()
        )
        let subject = makeSubject()

        let hash = try await subject.hash(
            graphTarget: graphTarget,
            hashedTargets: [:],
            hashedPaths: [:]
        ).hash

        #expect(hash == "package-foo-runtime-hash-hash")
    }

    private func makeSubject() -> DependenciesContentHasher {
        let contentHasher = MockContentHashing()
        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 + "-hash" }
        return DependenciesContentHasher(contentHasher: contentHasher)
    }
}
