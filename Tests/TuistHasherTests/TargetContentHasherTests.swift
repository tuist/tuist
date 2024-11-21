import Foundation
import Mockable
import Path
import TuistCore
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistHasher

final class TargetContentHasherTests: TuistUnitTestCase {
    private var contentHasher: MockContentHashing!
    private var coreDataModelsContentHasher: MockCoreDataModelsContentHashing!
    private var sourceFilesContentHasher: MockSourceFilesContentHashing!
    private var targetScriptsContentHasher: MockTargetScriptsContentHashing!
    private var resourcesContentHasher: MockResourcesContentHashing!
    private var copyFilesContentHasher: MockCopyFilesContentHashing!
    private var headersContentHasher: MockHeadersContentHashing!
    private var deploymentTargetContentHasher: MockDeploymentTargetsContentHashing!
    private var plistContentHasher: MockPlistContentHashing!
    private var settingsContentHasher: MockSettingsContentHashing!
    private var dependenciesContentHasher: MockDependenciesContentHashing!
    private var subject: TargetContentHasher!

    override func setUp() async throws {
        try await super.setUp()
        contentHasher = MockContentHashing()
        coreDataModelsContentHasher = MockCoreDataModelsContentHashing()
        sourceFilesContentHasher = MockSourceFilesContentHashing()
        targetScriptsContentHasher = MockTargetScriptsContentHashing()
        resourcesContentHasher = MockResourcesContentHashing()
        copyFilesContentHasher = MockCopyFilesContentHashing()
        headersContentHasher = MockHeadersContentHashing()
        deploymentTargetContentHasher = MockDeploymentTargetsContentHashing()
        plistContentHasher = MockPlistContentHashing()
        settingsContentHasher = MockSettingsContentHashing()
        dependenciesContentHasher = MockDependenciesContentHashing()
        subject = TargetContentHasher(
            contentHasher: contentHasher,
            sourceFilesContentHasher: sourceFilesContentHasher,
            targetScriptsContentHasher: targetScriptsContentHasher,
            coreDataModelsContentHasher: coreDataModelsContentHasher,
            resourcesContentHasher: resourcesContentHasher,
            copyFilesContentHasher: copyFilesContentHasher,
            headersContentHasher: headersContentHasher,
            deploymentTargetContentHasher: deploymentTargetContentHasher,
            plistContentHasher: plistContentHasher,
            settingsContentHasher: settingsContentHasher,
            dependenciesContentHasher: dependenciesContentHasher
        )

        given(contentHasher)
            .hash(Parameter<[String]>.any)
            .willProduce { $0.joined(separator: "-") }
    }

    override func tearDown() async throws {
        contentHasher = nil
        coreDataModelsContentHasher = nil
        sourceFilesContentHasher = nil
        targetScriptsContentHasher = nil
        resourcesContentHasher = nil
        copyFilesContentHasher = nil
        headersContentHasher = nil
        plistContentHasher = nil
        settingsContentHasher = nil
        dependenciesContentHasher = nil
        subject = nil
        try await super.tearDown()
    }

    func test_hash_when_targetBelongsToExternalProjectWithHash() async throws {
        // Given
        let target = GraphTarget.test(project: .test(type: .external(hash: "hash")))

        // When
        let got = try await subject.contentHash(for: target, hashedTargets: [:], hashedPaths: [:])

        // Then
        XCTAssertEqual(got.hash, "hash")
    }

    func test_hash_when_targetBelongsToExternalProjectWithHash_with_additional_string() async throws {
        // Given
        let target = GraphTarget.test(project: .test(type: .external(hash: "hash")))

        // When
        let got = try await subject.contentHash(
            for: target,
            hashedTargets: [:],
            hashedPaths: [:],
            additionalStrings: ["additional_string_one", "additional_string_two"]
        )

        // Then
        XCTAssertEqual(got.hash, "hash-additional_string_one-additional_string_two")
    }
}
