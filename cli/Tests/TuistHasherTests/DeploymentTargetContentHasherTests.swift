import Foundation
import Mockable
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
import Testing

@testable import TuistHasher

struct DeploymentTargetContentHasherTests {
    private let subject: DeploymentTargetsContentHasher
    private let contentHasher: MockContentHashing
    init() {
        contentHasher = .init()
        subject = DeploymentTargetsContentHasher(contentHasher: contentHasher)
        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 + "-hash" }
    }


    @Test
    func test_hash_whenIosIphoneV1_callsContentHasherWithExpectedStrings() throws {
        // When
        let deploymentTargets = DeploymentTargets.iOS("v1")

        // Then
        let hash = try subject.hash(deploymentTargets: deploymentTargets)
        #expect(hash == "iOS-v1-hash")
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
    }

    @Test
    func test_hash_whenIosIpadV2_callsContentHasherWithExpectedStrings() throws {
        // When
        let deploymentTargets = DeploymentTargets.iOS("v2")

        // Then
        let hash = try subject.hash(deploymentTargets: deploymentTargets)
        #expect(hash == "iOS-v2-hash")
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
    }

    @Test
    func test_hash_whenMacOSV2_callsContentHasherWithExpectedStrings() throws {
        // When
        let deploymentTargets = DeploymentTargets.macOS("v2")

        // Then
        let hash = try subject.hash(deploymentTargets: deploymentTargets)
        #expect(hash == "macOS-v2-hash")
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
    }

    @Test
    func test_hash_whenWatchOSV2_callsContentHasherWithExpectedStrings() throws {
        // When
        let deploymentTargets = DeploymentTargets.watchOS("v2")

        // Then
        let hash = try subject.hash(deploymentTargets: deploymentTargets)
        #expect(hash == "watchOS-v2-hash")
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
    }

    @Test
    func test_hash_whentvOSV2_callsContentHasherWithExpectedStrings() throws {
        // When
        let deploymentTargets = DeploymentTargets.tvOS("v2")

        // Then
        let hash = try subject.hash(deploymentTargets: deploymentTargets)
        #expect(hash == "tvOS-v2-hash")
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
    }
}
