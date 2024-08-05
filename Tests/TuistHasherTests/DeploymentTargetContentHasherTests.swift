import Foundation
import MockableTest
import Path
import TuistCore
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistHasher

final class DeploymentTargetContentHasherTests: TuistUnitTestCase {
    private var subject: DeploymentTargetsContentHasher!
    private var contentHasher: MockContentHashing!

    override func setUp() {
        super.setUp()
        contentHasher = .init()
        subject = DeploymentTargetsContentHasher(contentHasher: contentHasher)
        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 + "-hash" }
    }

    override func tearDown() {
        subject = nil
        contentHasher = nil
        super.tearDown()
    }

    func test_hash_whenIosIphoneV1_callsContentHasherWithExpectedStrings() throws {
        // When
        let deploymentTargets = DeploymentTargets.iOS("v1")

        // Then
        let hash = try subject.hash(deploymentTargets: deploymentTargets)
        XCTAssertEqual(hash, "iOS-v1-hash")
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
    }

    func test_hash_whenIosIpadV2_callsContentHasherWithExpectedStrings() throws {
        // When
        let deploymentTargets = DeploymentTargets.iOS("v2")

        // Then
        let hash = try subject.hash(deploymentTargets: deploymentTargets)
        XCTAssertEqual(hash, "iOS-v2-hash")
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
    }

    func test_hash_whenMacOSV2_callsContentHasherWithExpectedStrings() throws {
        // When
        let deploymentTargets = DeploymentTargets.macOS("v2")

        // Then
        let hash = try subject.hash(deploymentTargets: deploymentTargets)
        XCTAssertEqual(hash, "macOS-v2-hash")
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
    }

    func test_hash_whenWatchOSV2_callsContentHasherWithExpectedStrings() throws {
        // When
        let deploymentTargets = DeploymentTargets.watchOS("v2")

        // Then
        let hash = try subject.hash(deploymentTargets: deploymentTargets)
        XCTAssertEqual(hash, "watchOS-v2-hash")
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
    }

    func test_hash_whentvOSV2_callsContentHasherWithExpectedStrings() throws {
        // When
        let deploymentTargets = DeploymentTargets.tvOS("v2")

        // Then
        let hash = try subject.hash(deploymentTargets: deploymentTargets)
        XCTAssertEqual(hash, "tvOS-v2-hash")
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
    }
}
