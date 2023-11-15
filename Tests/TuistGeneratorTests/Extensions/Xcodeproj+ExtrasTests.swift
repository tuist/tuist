import TuistGraph
import TuistGraphTesting
import XcodeProj
import XCTest
@testable import TuistGenerator

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

    func test_platform_filter_application_when_matching() {
        // Given
        let target = Target.test(destinations: [.iPhone, .iPad, .mac])
        let buildFile = PBXBuildFile()
        let dependencyFilters: PlatformFilters = [.ios, .macos]

        // When
        buildFile.applyPlatformFilters(dependencyFilters, applicableTo: target)

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
    
    func test_platform_filter_application_when_all() {
        // Given
        let buildFile = PBXBuildFile()
        let dependencyFilters: PlatformFilters = .all

        // When
        buildFile.applyPlatformFilters(dependencyFilters)

        // Then
        XCTAssertNil(buildFile.platformFilter)
        XCTAssertNil(buildFile.platformFilters)
    }

    func test_platform_filter_application_when_target_has_less_than_dependency() {
        // Given
        let target = Target.test(destinations: [.mac])
        let buildFile = PBXBuildFile()
        let dependencyFilters: PlatformFilters = [.ios, .macos]

        // When
        buildFile.applyPlatformFilters(dependencyFilters, applicableTo: target)

        // Then
        XCTAssertNil(buildFile.platformFilter)
        XCTAssertNil(buildFile.platformFilters)
    }

    func test_platform_filter_application_when_target_has_more_than_dependency() {
        // Given
        let target = Target.test(destinations: [.iPhone, .iPad, .mac, .appleVision])
        let buildFile = PBXBuildFile()
        let dependencyFilters: PlatformFilters = [.ios, .macos]

        // When
        buildFile.applyPlatformFilters(dependencyFilters, applicableTo: target)

        // Then
        XCTAssertNil(buildFile.platformFilter)
        XCTAssertEqual(buildFile.platformFilters, ["ios", "macos"])
    }

    func test_platform_filter_application_when_target_has_single_intersection() {
        // Given
        let target = Target.test(destinations: [.iPhone, .iPad, .appleVision])
        let buildFile = PBXBuildFile()
        let dependencyFilters: PlatformFilters = [.ios, .macos]

        // When
        buildFile.applyPlatformFilters(dependencyFilters, applicableTo: target)

        // Then
        XCTAssertEqual(buildFile.platformFilter, "ios")
        XCTAssertNil(buildFile.platformFilters)
    }

    func test_platform_filter_application_when_disjoint() {
        // Given
        let target = Target.test(destinations: [.appleVision])
        let buildFile = PBXBuildFile()
        let dependencyFilters: PlatformFilters = [.macos]

        // When
        buildFile.applyPlatformFilters(dependencyFilters, applicableTo: target)

        // Then
        XCTAssertNil(buildFile.platformFilter)
        XCTAssertEqual(buildFile.platformFilters, ["macos"])
    }
}
