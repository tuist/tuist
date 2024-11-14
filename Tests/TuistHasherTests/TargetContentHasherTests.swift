import Foundation
import Mockable
import Path
import TuistCore
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistHasher

final class TargetContentHasherTests: TuistUnitTestCase {
    var contentHasher: MockContentHashing!
    var coreDataModelsContentHasher: MockCoreDataModelsContentHashing!
    var sourceFilesContentHasher: MockSourceFilesContentHashing!
    var targetScriptsContentHasher: MockTargetScriptsContentHashing!
    var resourcesContentHasher: MockResourcesContentHashing!
    var copyFilesContentHasher: MockCopyFilesContentHashing!
    var headersContentHasher: MockHeadersContentHashing!
    var deploymentTargetContentHasher: MockDeploymentTargetsContentHashing!
    var plistContentHasher: MockPlistContentHashing!
    var settingsContentHasher: MockSettingsContentHashing!
    var dependenciesContentHasher: MockDependenciesContentHashing!
    var subject: TargetContentHasher!

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
}
