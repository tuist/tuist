import Foundation
import TSCBasic
import TuistCacheTesting
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistSupport
import XCTest
@testable import TuistCache
@testable import TuistSupportTesting

final class DeploymentTargetContentHasherTests: TuistUnitTestCase {
    private var subject: DeploymentTargetsContentHasher!
    private var mockContentHasher: MockContentHasher!

    override func setUp() {
        super.setUp()
        mockContentHasher = MockContentHasher()
        subject = DeploymentTargetsContentHasher(contentHasher: mockContentHasher)
    }

    override func tearDown() {
        subject = nil
        mockContentHasher = nil
        super.tearDown()
    }

    func test_hash_whenIosIphoneV1_callsContentHasherWithExpectedStrings() throws {
        // When
        //, .iphone, supportsMacDesignedForIOS: false
        let deploymentTargets = DeploymentTargets.iOS("v1")

        // Then
        let hash = try subject.hash(deploymentTargets: deploymentTargets)
        XCTAssertEqual(hash, "iOS-v1-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenIosIpadV2_callsContentHasherWithExpectedStrings() throws {
        // When
        let deploymentTargets = DeploymentTargets.iOS("v2")

        // Then
        let hash = try subject.hash(deploymentTargets: deploymentTargets)
        XCTAssertEqual(hash, "iOS-v2-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenMacOSV2_callsContentHasherWithExpectedStrings() throws {
        // When
        let deploymentTargets = DeploymentTargets.macOS("v2")

        // Then
        let hash = try subject.hash(deploymentTargets: deploymentTargets)
        XCTAssertEqual(hash, "macOS-v2-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenWatchOSV2_callsContentHasherWithExpectedStrings() throws {
        // When
        let deploymentTargets = DeploymentTargets.watchOS("v2")

        // Then
        let hash = try subject.hash(deploymentTargets: deploymentTargets)
        XCTAssertEqual(hash, "watchOS-v2-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whentvOSV2_callsContentHasherWithExpectedStrings() throws {
        // When
        let deploymentTargets = DeploymentTargets.tvOS("v2")

        // Then
        let hash = try subject.hash(deploymentTargets: deploymentTargets)
        XCTAssertEqual(hash, "tvOS-v2-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }
}
