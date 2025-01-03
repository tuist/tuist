import Foundation
import Mockable
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

        given(settingsContentHasher)
            .hash(settings: .any)
            .willReturn("settings_hash")
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
        XCTAssertEqual(got.hash, "hash-app-settings_hash-iPad-iPhone")
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
        XCTAssertEqual(got.hash, "hash-app-settings_hash-iPad-iPhone-additional_string_one-additional_string_two")
    }

    func test_hash_with_additional_strings() async throws {
        // Given
        let target = GraphTarget.test(project: .test())
        given(sourceFilesContentHasher)
            .hash(identifier: .any, sources: .any)
            .willReturn(MerkleNode(hash: "sources_hash", identifier: "sources"))
        given(resourcesContentHasher)
            .hash(identifier: .any, resources: .any)
            .willReturn(MerkleNode(hash: "resources_hash", identifier: "resources"))
        given(copyFilesContentHasher)
            .hash(identifier: .any, copyFiles: .any)
            .willReturn(MerkleNode(hash: "copy_files_hash", identifier: "copy_files"))
        given(coreDataModelsContentHasher!)
            .hash(coreDataModels: .any)
            .willReturn("core_data_models_hash")
        given(dependenciesContentHasher)
            .hash(graphTarget: .any, hashedTargets: .any, hashedPaths: .any)
            .willReturn(DependenciesContentHash(hashedPaths: [:], hash: "dependencies_hash"))
        given(targetScriptsContentHasher)
            .hash(targetScripts: .any, sourceRootPath: .any)
            .willReturn("target_scripts_hash")
        given(contentHasher)
            .hash(Parameter<[String: String]>.any)
            .willReturn("dictionary_hash")
        given(deploymentTargetContentHasher)
            .hash(deploymentTargets: .any)
            .willReturn("deployment_targets_hash")

        // When
        let got = try await subject.contentHash(
            for: target,
            hashedTargets: [:],
            hashedPaths: [:],
            additionalStrings: ["additional_string"]
        )

        // Then
        XCTAssertEqual(
            got.hash,
            "Target-app-io.tuist.Target-Target-dependencies_hash-sources_hash-resources_hash-copy_files_hash-core_data_models_hash-target_scripts_hash-dictionary_hash-iPad-iPhone-additional_string-iPad-iPhone-deployment_targets_hash-settings_hash"
        )
    }
}
