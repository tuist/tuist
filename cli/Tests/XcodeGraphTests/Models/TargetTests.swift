import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class TargetTests: XCTestCase {
    func test_codable() {
        // Given
        let subject = Target.test(name: "Test", product: .staticLibrary)

        // Then
        XCTAssertCodable(subject)
    }

    func test_sequence_testBundles() {
        let app = Target.test(product: .app)
        let tests = Target.test(product: .unitTests)
        let targets = [app, tests]

        XCTAssertEqual(targets.testBundles, [tests])
    }

    func test_sequence_apps() {
        let app = Target.test(product: .app)
        let tests = Target.test(product: .unitTests)
        let targets = [app, tests]

        XCTAssertEqual(targets.apps, [app])
    }

    func test_sequence_appClips() {
        let appClip = Target.test(product: .appClip)
        let tests = Target.test(product: .unitTests)
        let targets = [appClip, tests]

        XCTAssertEqual(targets.apps, [appClip])
    }

    func test_dependencyPlatformFilters_when_iOS_targets_mac() {
        // Given
        let target = Target.test(destinations: [.macCatalyst])

        // When
        let got = target.dependencyPlatformFilters

        // Then
        XCTAssertEqual(got, [PlatformFilter.catalyst])
    }

    func test_dependencyPlatformFilters_when_iOS_and_doesnt_target_mac() {
        // Given
        let target = Target.test(destinations: .iOS)

        // When
        let got = target.dependencyPlatformFilters

        // Then
        XCTAssertEqual(got, [PlatformFilter.ios])
    }

    func test_dependencyPlatformFilters_when_iOS_and_catalyst() {
        // Given
        let target = Target.test(destinations: [.iPhone, .iPad, .macCatalyst])

        // When
        let got = target.dependencyPlatformFilters

        // Then
        XCTAssertEqual(got, [PlatformFilter.ios, PlatformFilter.catalyst])
    }

    func test_dependencyPlatformFilters_when_using_many_destinations() {
        // Given
        let target = Target.test(destinations: [.iPhone, .iPad, .macCatalyst, .mac, .appleVision])

        // When
        let got = target.dependencyPlatformFilters

        // Then
        XCTAssertEqual(got, [PlatformFilter.ios, PlatformFilter.catalyst, PlatformFilter.macos, PlatformFilter.visionos])
    }

    func test_supportsCatalyst_returns_true_when_the_destinations_include_macCatalyst() {
        // Given
        let target = Target.test(destinations: [.macCatalyst])

        // When
        let got = target.supportsCatalyst

        // Then
        XCTAssertTrue(got)
    }

    func test_supportsCatalyst_returns_false_when_the_destinations_include_macCatalyst() {
        // Given
        let target = Target.test(destinations: [.iPad])

        // When
        let got = target.supportsCatalyst

        // Then
        XCTAssertFalse(got)
    }

    func test_supportsResources_returns_true_for_static_frameworks() {
        // Given
        let target = Target.test(product: .staticFramework)

        // When
        let got = target.supportsResources

        // Then
        XCTAssertTrue(got)
    }

    func test_supportsResources_returns_true_for_command_line_tools() {
        // Given
        let target = Target.test(destinations: .macOS, product: .commandLineTool)

        // When
        let got = target.supportsResources

        // Then
        XCTAssertTrue(got)
    }

    func test_supportsResources_returns_true_for_macros() {
        // Given
        let target = Target.test(destinations: .macOS, product: .macro)

        // When
        let got = target.supportsResources

        // Then
        XCTAssertTrue(got)
    }

    func test_supportsResources_returns_true_for_xpc_services() {
        // Given
        let target = Target.test(destinations: .macOS, product: .xpc)

        // When
        let got = target.supportsResources

        // Then
        XCTAssertTrue(got)
    }

    func test_supportsResources_returns_false_for_static_libraries() {
        // Given
        let target = Target.test(product: .staticLibrary)

        // When
        let got = target.supportsResources

        // Then
        XCTAssertFalse(got)
    }

    func test_supportsResources_returns_false_for_dynamic_libraries() {
        // Given
        let target = Target.test(product: .dynamicLibrary)

        // When
        let got = target.supportsResources

        // Then
        XCTAssertFalse(got)
    }
}
