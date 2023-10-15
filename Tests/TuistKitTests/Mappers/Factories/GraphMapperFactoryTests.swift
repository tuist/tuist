import Foundation
import TSCBasic
import TuistAutomation
import TuistCoreTesting
import TuistGraph
import TuistLoader
import TuistSigning
import XCTest
#if canImport(TuistCloud)
    @testable import TuistCloud
    @testable import TuistCloudTesting
#endif
@testable import TuistCore
@testable import TuistGenerator
@testable import TuistKit
@testable import TuistSupportTesting

final class GraphMapperFactoryTests: TuistUnitTestCase {
    var subject: GraphMapperFactory!

    override func setUp() {
        super.setUp()
        subject = GraphMapperFactory(contentHasher: ContentHasher())
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_default_contains_the_update_workspace_projects_graph_mapper() {
        // When
        let got = subject.default()

        // Then
        XCTAssertContainsElementOfType(got, UpdateWorkspaceProjectsGraphMapper.self)
    }

    #if canImport(TuistCloud)
        func test_cache_contains_the_filter_target_dependenies_tree_graph_mapper() {
            // Given
            let includedTargets = Set(["MyTarget"])

            // When
            let got = subject.cache(includedTargets: includedTargets)

            // Then
            let mapper = XCTAssertContainsElementOfType(got, FocusTargetsGraphMappers.self)
            XCTAssertEqual(mapper?.includedTargets, includedTargets)
        }
    #endif

    #if canImport(TuistCloud)
        func test_cache_contains_the_tree_shaking_mapper() {
            // Given
            let includedTargets = Set(["MyTarget"])

            // When
            let got = subject.cache(includedTargets: includedTargets)

            // Then
            XCTAssertContainsElementOfType(got, TreeShakePrunedTargetsGraphMapper.self, after: FocusTargetsGraphMappers.self)
        }
    #endif

    #if canImport(TuistCloud)
        func test_focus_contains_the_filter_target_dependenies_tree_graph_mapper() {
            // Given
            let config = Config.test()
            let cacheSources = Set(["MyTarget"])
            let cacheProfile = Cache.Profile.test()
            let cacheOutputType = CacheOutputType.framework

            // When
            let got = subject.focus(
                config: config,
                cache: true,
                cacheSources: cacheSources,
                cacheProfile: cacheProfile,
                cacheOutputType: cacheOutputType,
                targetsToSkipCache: []
            )

            // Then
            let mapper = XCTAssertContainsElementOfType(got, FocusTargetsGraphMappers.self)
            XCTAssertEqual(mapper?.includedTargets, cacheSources)
        }
    #endif

    #if canImport(TuistCloud)
        func test_focus_contains_the_cache_tree_shaking_graph_mapper() {
            // Given
            let config = Config.test()
            let cacheSources = Set(["MyTarget"])
            let cacheProfile = Cache.Profile.test()
            let cacheOutputType = CacheOutputType.framework

            // When
            let got = subject.focus(
                config: config,
                cache: true,
                cacheSources: cacheSources,
                cacheProfile: cacheProfile,
                cacheOutputType: cacheOutputType,
                targetsToSkipCache: []
            )

            // Then
            XCTAssertContainsElementOfType(got, TreeShakePrunedTargetsGraphMapper.self, after: FocusTargetsGraphMappers.self)
            XCTAssertContainsElementOfType(
                got,
                TreeShakePrunedTargetsGraphMapper.self,
                after: TargetsToCacheBinariesGraphMapper.self
            )
        }
    #endif

    #if canImport(TuistCloud)
        func test_focus_contains_the_cache_mapper() {
            // Given
            let config = Config.test()
            let cacheSources = Set(["MyTarget"])
            let cacheProfile = Cache.Profile.test()
            let cacheOutputType = CacheOutputType.framework

            // When
            let got = subject.focus(
                config: config,
                cache: true,
                cacheSources: cacheSources,
                cacheProfile: cacheProfile,
                cacheOutputType: cacheOutputType,
                targetsToSkipCache: []
            )

            // Then
            XCTAssertContainsElementOfType(got, TargetsToCacheBinariesGraphMapper.self, after: FocusTargetsGraphMappers.self)
        }
    #endif

    #if canImport(TuistCloud)
        func test_automation_contains_the_tests_cache_graph_mapper() throws {
            // Given
            let config = Config.test()
            let testsCacheDirectory = try temporaryPath()

            // When
            let got = subject.automation(
                config: config,
                cache: false,
                testsCacheDirectory: testsCacheDirectory,
                testPlan: nil,
                includedTargets: [],
                excludedTargets: [],
                cacheProfile: .test(),
                cacheOutputType: .framework,
                targetsToSkipCache: []
            )

            // Then
            let mapper = XCTAssertContainsElementOfType(got, TestsCacheGraphMapper.self)
            XCTAssertEqual(mapper?.hashesCacheDirectory, testsCacheDirectory)
            XCTAssertEqual(mapper?.config, config)
        }
    #endif

    #if canImport(TuistCloud)
        func test_automation_contains_the_filter_target_dependenies_tree_graph_mapper() throws {
            // Given
            let config = Config.test()
            let testsCacheDirectory = try temporaryPath()

            // When
            let got = subject.automation(
                config: config,
                cache: false,
                testsCacheDirectory: testsCacheDirectory,
                testPlan: nil,
                includedTargets: [],
                excludedTargets: [],
                cacheProfile: .test(),
                cacheOutputType: .framework,
                targetsToSkipCache: []
            )

            // Then
            XCTAssertContainsElementOfType(got, FocusTargetsGraphMappers.self, after: TestsCacheGraphMapper.self)
        }
    #endif

    #if canImport(TuistCloud)
        func test_automation_contains_the_tests_cache_tree_shaking_mapper() throws {
            // Given
            let config = Config.test()
            let testsCacheDirectory = try temporaryPath()

            // When
            let got = subject.automation(
                config: config,
                cache: false,
                testsCacheDirectory: testsCacheDirectory,
                testPlan: nil,
                includedTargets: [],
                excludedTargets: [],
                cacheProfile: .test(),
                cacheOutputType: .framework,
                targetsToSkipCache: []
            )

            // Then
            XCTAssertContainsElementOfType(got, TreeShakePrunedTargetsGraphMapper.self, after: FocusTargetsGraphMappers.self)
        }
    #endif
}
