import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistLoader
@testable import TuistSupportTesting

final class ManifestFilesLocatorTests: TuistUnitTestCase {
    private var subject: ManifestFilesLocator!

    override func setUp() {
        super.setUp()
        subject = ManifestFilesLocator()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_locateProjectManifests_returns_all_manifest_no_workspace_given_child_path() throws {
        // Given
        let paths = try createFiles([
            "Module/Project.swift",
            "Project.swift",
            "Tuist/Config.swift",
        ])

        // When
        let manifests = subject.locateProjectManifests(at: paths.first!)

        // Then
        XCTAssertEqual(manifests.count, 2)
        XCTAssertEqual(manifests.first?.0, Manifest.project)
        XCTAssertEqual(manifests.first?.1, paths.first)
        XCTAssertEqual(manifests.last?.0, Manifest.project)
        XCTAssertEqual(manifests.last?.1, paths.dropLast().last)
    }

    func test_locateProjectManifests_returns_all_manifest_with_workspace_given_child_path() throws {
        // Given
        let paths = try createFiles([
            "Module/Project.swift",
            "Workspace.swift",
            "Tuist/Config.swift",
        ])

        // When
        let manifests = subject.locateProjectManifests(at: paths.first!)

        // Then
        XCTAssertEqual(manifests.first?.0, Manifest.project)
        XCTAssertEqual(manifests.first?.1, paths.first)
        XCTAssertEqual(manifests.last?.0, Manifest.workspace)
        XCTAssertEqual(manifests.last?.1, paths.dropLast().last)
    }

    func test_locateProjectManifests_falls_back_to_locatingPath_given_no_root_path() throws {
        // Given
        let paths = try createFiles([
            "A/Project.swift",
            "B/Workspace.swift",
            "C/Project.swift",
        ])

        // When
        let manifests = subject
            .locateProjectManifests(at: try temporaryPath())
            .sorted(by: { $0.1 < $1.1 })

        // Then
        XCTAssertEqual(manifests[0].0, Manifest.project)
        XCTAssertEqual(manifests[0].1, paths[0])

        XCTAssertEqual(manifests[1].0, Manifest.workspace)
        XCTAssertEqual(manifests[1].1, paths[1])

        XCTAssertEqual(manifests[2].0, Manifest.project)
        XCTAssertEqual(manifests[2].1, paths[2])
    }

    func test_locatePluginManifests_returns_all_plugins_when_given_root_path() throws {
        // Given
        let paths = try createFiles([
            "Plugin.swift",
            "A/Plugin.swift",
            "B/Plugin.swift",
            "B/C/Plugin.swift",
        ])

        // When
        let manifests = subject.locatePluginManifests(
            at: paths[0] // Plugin.swift
        )

        // Then
        XCTAssertEqual(manifests[0], paths[1]) // A/Plugin.swift
        XCTAssertEqual(manifests[1], paths[3]) // B/C/Plugin.swift
        XCTAssertEqual(manifests[2], paths[2]) // B/Plugin.swift
        XCTAssertEqual(manifests[3], paths[0]) // Plugin.swift
    }

    func test_locatePluginManifests_returns_plugin_when_given_child_path() throws {
        // Given
        let paths = try createFiles([
            "A/Plugin.swift",
            "A/Helpers/Helper.swift",
        ])

        // When
        let manifests = subject.locatePluginManifests(
            at: paths[1] // A/Helpers/Helper.swift
        )

        // Then
        XCTAssertEqual(manifests[0], paths[0]) // A/Plugin.swift
    }

    func test_locatePluginManifests_falls_back_to_locatingPath_when_no_root_path() throws {
        // Given
        let paths = try createFiles([
            "A/Plugin.swift",
            "B/Plugin.swift",
        ])

        // When
        let manifests = subject.locatePluginManifests(at: try temporaryPath())

        // Then
        XCTAssertEqual(manifests[0], paths[0])
        XCTAssertEqual(manifests[1], paths[1])
    }

    func test_locateConfig() throws {
        // Given
        let paths = try createFiles([
            "Module01/File01.swift",
            "Module01/File02.swift",
            "Module01/File03.swift",

            "Module02/File01.swift",
            "Module02/File01.swift",
            "Module02/Subdir01/File01.swift",
            "Module02/Subdir01/File02.swift",

            "File01.swift",
            "File02.swift",
            "Tuist/Config.swift",
        ])

        // When
        let configPath = subject.locateConfig(at: try temporaryPath())

        // Then
        XCTAssertNotNil(configPath)
        XCTAssertEqual(paths.last, configPath)
    }

    func test_locateConfig_traversing() throws {
        // Given
        let paths = try createFiles([
            "Module01/File01.swift",
            "Module01/File02.swift",
            "Module01/File03.swift",

            "Module02/File01.swift",
            "Module02/File01.swift",
            "Module02/Subdir01/File01.swift",
            "Module02/Subdir01/File02.swift",

            "File01.swift",
            "File02.swift",
            "Tuist/Config.swift",
        ])
        let locatingPath = paths[5] // "Module02/Subdir01/File01.swift"

        // When
        let configPath = subject.locateConfig(at: locatingPath)

        // Then
        XCTAssertNotNil(configPath)
        XCTAssertEqual(paths.last, configPath)
    }

    func test_locateConfig_where_config_not_exist() throws {
        // Given
        try createFiles([
            "Module01/File01.swift",
            "Module01/File02.swift",
            "Module01/File03.swift",

            "Module02/File01.swift",
            "Module02/File01.swift",
            "Module02/Subdir01/File01.swift",
            "Module02/Subdir01/File02.swift",

            "File01.swift",
            "File02.swift",
        ])

        // When
        let configPath = subject.locateConfig(at: try temporaryPath())

        // Then
        XCTAssertNil(configPath)
    }

    func test_locateConfig_traversing_where_config_not_exist() throws {
        // Given
        let paths = try createFiles([
            "Module01/File01.swift",
            "Module01/File02.swift",
            "Module01/File03.swift",

            "Module02/File01.swift",
            "Module02/File01.swift",
            "Module02/Subdir01/File01.swift",
            "Module02/Subdir01/File02.swift",

            "File01.swift",
            "File02.swift",
        ])
        let locatingPath = paths[5] // "Module02/Subdir01/File01.swift"

        // When
        let configPath = subject.locateConfig(at: locatingPath)

        // Then
        XCTAssertNil(configPath)
    }

    func test_locateDependencies() throws {
        // Given
        let paths = try createFiles([
            "Module01/File01.swift",
            "Module01/File02.swift",
            "Module01/File03.swift",

            "Module02/File01.swift",
            "Module02/File01.swift",
            "Module02/Subdir01/File01.swift",
            "Module02/Subdir01/File02.swift",

            "File01.swift",
            "File02.swift",
            "Tuist/Dependencies.swift",
        ])

        // When
        let dependenciesPath = subject.locateDependencies(at: try temporaryPath())

        // Then
        XCTAssertNotNil(dependenciesPath)
        XCTAssertEqual(paths.last, dependenciesPath)
    }

    func test_locateDependencies_traversing() throws {
        // Given
        let paths = try createFiles([
            "Module01/File01.swift",
            "Module01/File02.swift",
            "Module01/File03.swift",

            "Module02/File01.swift",
            "Module02/File01.swift",
            "Module02/Subdir01/File01.swift",
            "Module02/Subdir01/File02.swift",

            "File01.swift",
            "File02.swift",
            "Tuist/Dependencies.swift",
        ])
        let locatingPath = paths[5] // "Module02/Subdir01/File01.swift"

        // When
        let dependenciesPath = subject.locateDependencies(at: locatingPath)

        // Then
        XCTAssertNotNil(dependenciesPath)
        XCTAssertEqual(paths.last, dependenciesPath)
    }

    func test_locateDependencies_where_config_not_exist() throws {
        // Given
        try createFiles([
            "Module01/File01.swift",
            "Module01/File02.swift",
            "Module01/File03.swift",

            "Module02/File01.swift",
            "Module02/File01.swift",
            "Module02/Subdir01/File01.swift",
            "Module02/Subdir01/File02.swift",

            "File01.swift",
            "File02.swift",
        ])

        // When
        let dependenciesPath = subject.locateDependencies(at: try temporaryPath())

        // Then
        XCTAssertNil(dependenciesPath)
    }

    func test_locateDependencies_traversing_where_config_not_exist() throws {
        // Given
        let paths = try createFiles([
            "Module01/File01.swift",
            "Module01/File02.swift",
            "Module01/File03.swift",

            "Module02/File01.swift",
            "Module02/File01.swift",
            "Module02/Subdir01/File01.swift",
            "Module02/Subdir01/File02.swift",

            "File01.swift",
            "File02.swift",
        ])
        let locatingPath = paths[5] // "Module02/Subdir01/File01.swift"

        // When
        let dependenciesPath = subject.locateDependencies(at: locatingPath)

        // Then
        XCTAssertNil(dependenciesPath)
    }

    func test_locateSetup() throws {
        // Given
        let paths = try createFiles([
            "Module01/File01.swift",
            "Module01/File02.swift",
            "Module01/File03.swift",

            "Module02/File01.swift",
            "Module02/File01.swift",
            "Module02/Subdir01/File01.swift",
            "Module02/Subdir01/File02.swift",

            "File01.swift",
            "File02.swift",
            "Setup.swift",
        ])

        // When
        let setupPath = subject.locateSetup(at: try temporaryPath())

        // Then
        XCTAssertNotNil(setupPath)
        XCTAssertEqual(paths.last, setupPath)
    }

    func test_locateSetup_traversing() throws {
        // Given
        let paths = try createFiles([
            "Module01/File01.swift",
            "Module01/File02.swift",
            "Module01/File03.swift",

            "Module02/File01.swift",
            "Module02/File01.swift",
            "Module02/Subdir01/File01.swift",
            "Module02/Subdir01/File02.swift",

            "File01.swift",
            "File02.swift",
            "Setup.swift",
        ])
        let locatingPath = paths[5] // "Module02/Subdir01/File01.swift"

        // When
        let setupPath = subject.locateSetup(at: locatingPath)

        // Then
        XCTAssertNotNil(setupPath)
        XCTAssertEqual(paths.last, setupPath)
    }

    func test_locateSetup_where_setup_not_exist() throws {
        // Given
        try createFiles([
            "Module01/File01.swift",
            "Module01/File02.swift",
            "Module01/File03.swift",

            "Module02/File01.swift",
            "Module02/File01.swift",
            "Module02/Subdir01/File01.swift",
            "Module02/Subdir01/File02.swift",

            "File01.swift",
            "File02.swift",
        ])

        // When
        let setupPath = subject.locateSetup(at: try temporaryPath())

        // Then
        XCTAssertNil(setupPath)
    }

    func test_locateSetup_traversing_where_setup_not_exist() throws {
        // Given
        let paths = try createFiles([
            "Module01/File01.swift",
            "Module01/File02.swift",
            "Module01/File03.swift",

            "Module02/File01.swift",
            "Module02/File01.swift",
            "Module02/Subdir01/File01.swift",
            "Module02/Subdir01/File02.swift",

            "File01.swift",
            "File02.swift",
        ])
        let locatingPath = paths[5] // "Module02/Subdir01/File01.swift"

        // When
        let setupPath = subject.locateSetup(at: locatingPath)

        // Then
        XCTAssertNil(setupPath)
    }
}
