import TuistGraph
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistGraphTesting

class XcodeprojExtrasTests: XCTestCase {
    func test_pbxFileElement_sort() {
        // Given
        let elements = [
            PBXFileReference(name: "d"),
            PBXGroup(name: "E"),
            PBXFileReference(name: "r"),
            PBXGroup(name: "Z"),
            PBXFileReference(name: "c"),
            PBXGroup(name: "A"),
        ]

        // When
        let sorted = elements.sorted(by: PBXFileElement.filesBeforeGroupsSort)

        // Then
        XCTAssertEqual(sorted.map(\.nameOrPath), [
            // Files
            "c",
            "d",
            "r",

            // Groups
            "A",
            "E",
            "Z",
        ])
    }

    func test_platform_filter_application_when_matching() throws {
        // Given
        let target = Target.test(destinations: [.iPhone, .iPad, .mac])
        let buildFile = PBXBuildFile()
        let dependencyCondition: PlatformCondition = try .test([.ios, .macos])

        // When
        buildFile.applyCondition(dependencyCondition, applicableTo: target)

        // Then
        XCTAssertNil(buildFile.platformFilter)
        XCTAssertNil(buildFile.platformFilters)
    }

    func test_platform_filter_application_when_empty() {
        // Given
        let buildFile = PBXBuildFile()
        let dependencyFilters: PlatformFilters = []

        // When
        buildFile.applyPlatformFilters(dependencyFilters)

        // Then
        XCTAssertNil(buildFile.platformFilter)
        XCTAssertNil(buildFile.platformFilters)
    }

    func test_platform_filter_application_when_target_has_less_than_dependency() throws {
        // Given
        let target = Target.test(destinations: [.mac])
        let buildFile = PBXBuildFile()
        let dependencyCondition: PlatformCondition = try .test([.ios, .macos])

        // When
        buildFile.applyCondition(dependencyCondition, applicableTo: target)

        // Then
        XCTAssertNil(buildFile.platformFilter)
        XCTAssertNil(buildFile.platformFilters)
    }

    func test_platform_filter_application_when_target_has_more_than_dependency() throws {
        // Given
        let target = Target.test(destinations: [.iPhone, .iPad, .mac, .appleVision])
        let buildFile = PBXBuildFile()
        let dependencyCondition: PlatformCondition = try .test([.ios, .macos])

        // When
        buildFile.applyCondition(dependencyCondition, applicableTo: target)

        // Then
        XCTAssertNil(buildFile.platformFilter)
        XCTAssertEqual(buildFile.platformFilters, ["ios", "macos"])
    }

    func test_platform_filter_application_when_target_has_single_intersection() throws {
        // Given
        let target = Target.test(destinations: [.iPhone, .iPad, .appleVision])
        let buildFile = PBXBuildFile()
        let dependencyCondition: PlatformCondition = try .test([.ios, .macos])

        // When
        buildFile.applyCondition(dependencyCondition, applicableTo: target)

        // Then
        XCTAssertEqual(buildFile.platformFilter, "ios")
        XCTAssertNil(buildFile.platformFilters)
    }

    func test_platform_filter_application_when_disjoint() throws {
        // Given
        let target = Target.test(destinations: [.appleVision])
        let buildFile = PBXBuildFile()
        let dependencyCondition: PlatformCondition = try .test([.macos])

        // When
        buildFile.applyCondition(dependencyCondition, applicableTo: target)

        // Then
        XCTAssertNil(buildFile.platformFilter)
        XCTAssertEqual(buildFile.platformFilters, ["macos"])
    }
}
