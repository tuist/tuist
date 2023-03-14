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
    private var subject: DeploymentTargetContentHasher!
    private var mockContentHasher: MockContentHasher!

    override func setUp() {
        super.setUp()
        mockContentHasher = MockContentHasher()
        subject = DeploymentTargetContentHasher(contentHasher: mockContentHasher)
    }

    override func tearDown() {
        subject = nil
        mockContentHasher = nil
        super.tearDown()
    }

    func test_hash_whenIosIphoneV1_callsContentHasherWithExpectedStrings() throws {
        // When
        let deploymentTarget = DeploymentTarget.iOS("v1", .iphone, supportsMacDesignedForIOS: false)

        // Then
        let hash = try subject.hash(deploymentTarget: deploymentTarget)
        XCTAssertEqual(hash, "iOS-v1-1-false-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenIosIpadV2_callsContentHasherWithExpectedStrings() throws {
        // When
        let deploymentTarget = DeploymentTarget.iOS("v2", .ipad, supportsMacDesignedForIOS: true)

        // Then
        let hash = try subject.hash(deploymentTarget: deploymentTarget)
        XCTAssertEqual(hash, "iOS-v2-2-true-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenMacOSV2_callsContentHasherWithExpectedStrings() throws {
        // When
        let deploymentTarget = DeploymentTarget.macOS("v2")

        // Then
        let hash = try subject.hash(deploymentTarget: deploymentTarget)
        XCTAssertEqual(hash, "macOS-v2-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenWatchOSV2_callsContentHasherWithExpectedStrings() throws {
        // When
        let deploymentTarget = DeploymentTarget.watchOS("v2")

        // Then
        let hash = try subject.hash(deploymentTarget: deploymentTarget)
        XCTAssertEqual(hash, "watchOS-v2-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whentvOSV2_callsContentHasherWithExpectedStrings() throws {
        // When
        let deploymentTarget = DeploymentTarget.tvOS("v2")

        // Then
        let hash = try subject.hash(deploymentTarget: deploymentTarget)
        XCTAssertEqual(hash, "tvOS-v2-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }
}
