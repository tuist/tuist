import Testing
import XcodeGraph
import XcodeProj
@testable import TuistGenerator

struct XcodeprojExtrasTests {
    @Test
    func pbxFileElement_sort() {
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
        #expect(sorted.map(\.nameOrPath) == [
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

    @Test
    func platform_filter_application_when_matching() throws {
        // Given
        let target = Target.test(destinations: [.iPhone, .iPad, .mac])
        let buildFile = PBXBuildFile()
        let dependencyCondition: PlatformCondition = try #require(try PlatformCondition.test([.ios, .macos]))

        // When
        buildFile.applyCondition(dependencyCondition, applicableTo: target)

        // Then
        #expect(buildFile.platformFilter == nil)
        #expect(buildFile.platformFilters == nil)
    }

    @Test
    func platform_filter_application_when_empty() {
        // Given
        let buildFile = PBXBuildFile()
        let dependencyFilters: PlatformFilters = []

        // When
        buildFile.applyPlatformFilters(dependencyFilters)

        // Then
        #expect(buildFile.platformFilter == nil)
        #expect(buildFile.platformFilters == nil)
    }

    @Test
    func platform_filter_application_when_target_has_less_than_dependency() throws {
        // Given
        let target = Target.test(destinations: [.mac])
        let buildFile = PBXBuildFile()
        let dependencyCondition: PlatformCondition = try #require(try PlatformCondition.test([.ios, .macos]))

        // When
        buildFile.applyCondition(dependencyCondition, applicableTo: target)

        // Then
        #expect(buildFile.platformFilter == nil)
        #expect(buildFile.platformFilters == nil)
    }

    @Test
    func platform_filter_application_when_target_has_more_than_dependency() throws {
        // Given
        let target = Target.test(destinations: [.iPhone, .iPad, .mac, .appleVision])
        let buildFile = PBXBuildFile()
        let dependencyCondition: PlatformCondition = try #require(try PlatformCondition.test([.ios, .macos]))

        // When
        buildFile.applyCondition(dependencyCondition, applicableTo: target)

        // Then
        #expect(buildFile.platformFilter == nil)
        #expect(buildFile.platformFilters == ["ios", "macos"])
    }

    @Test
    func platform_filter_application_when_target_has_single_intersection() throws {
        // Given
        let target = Target.test(destinations: [.iPhone, .iPad, .appleVision])
        let buildFile = PBXBuildFile()
        let dependencyCondition: PlatformCondition = try #require(try PlatformCondition.test([.ios, .macos]))

        // When
        buildFile.applyCondition(dependencyCondition, applicableTo: target)

        // Then
        #expect(buildFile.platformFilter == "ios")
        #expect(buildFile.platformFilters == nil)
    }

    @Test
    func platform_filter_application_when_disjoint() throws {
        // Given
        let target = Target.test(destinations: [.appleVision])
        let buildFile = PBXBuildFile()
        let dependencyCondition: PlatformCondition = try #require(try PlatformCondition.test([.macos]))

        // When
        buildFile.applyCondition(dependencyCondition, applicableTo: target)

        // Then
        #expect(buildFile.platformFilter == nil)
        #expect(buildFile.platformFilters == ["macos"])
    }
}
