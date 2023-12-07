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
        let tuistManifestSignature = "import ProjectDescription"
        let paths = try createFiles([
            "Module/Project.swift",
            "Project.swift",
            "Tuist/Config.swift",
        ], content: tuistManifestSignature)

        // When
        let manifests = subject
            .locateProjectManifests(at: paths.first!, excluding: [], onlyCurrentDirectory: false)
            .sorted(by: { $0.path < $1.path })

        // Then
        XCTAssertEqual(
            manifests,
            [
                ManifestFilesLocator.ProjectManifest(
                    manifest: .project,
                    path: paths[0]
                ),
                ManifestFilesLocator.ProjectManifest(
                    manifest: .project,
                    path: paths[1]
                ),
            ]
        )
    }

    func test_locateProjectManifests_returns_all_manifest_with_workspace_given_child_path() throws {
        // Given
        let tuistManifestSignature = "import ProjectDescription"
        let paths = try createFiles([
            "Module/Project.swift",
            "Workspace.swift",
            "Tuist/Config.swift",
        ], content: tuistManifestSignature)

        // When
        let manifests = subject
            .locateProjectManifests(at: paths.first!, excluding: [], onlyCurrentDirectory: false)
            .sorted(by: { $0.path < $1.path })

        // Then
        XCTAssertEqual(
            manifests,
            [
                ManifestFilesLocator.ProjectManifest(
                    manifest: .project,
                    path: paths[0]
                ),
                ManifestFilesLocator.ProjectManifest(
                    manifest: .workspace,
                    path: paths[1]
                ),
            ]
        )
    }

    func test_locateProjectManifests_returns_only_manifest_in_locating_path_when_only_current_directory() throws {
        // Given
        let paths = try createFiles([
            "Workspace.swift",
            "Module/Project.swift",
            "Tuist/Config.swift",
        ])

        // When
        let manifests = subject
            .locateProjectManifests(at: paths.first!.parentDirectory, excluding: [], onlyCurrentDirectory: true)
            .sorted(by: { $0.path < $1.path })

        // Then
        XCTAssertEqual(
            manifests,
            [
                ManifestFilesLocator.ProjectManifest(
                    manifest: Manifest.workspace,
                    path: paths[0]
                ),
            ]
        )
    }

    func test_locateProjectManifests_falls_back_to_locatingPath_given_no_root_path() throws {
        // Given
        let tuistManifestSignature = "import ProjectDescription"
        let paths = try createFiles([
            "A/Project.swift",
            "B/Workspace.swift",
            "C/Project.swift",
        ], content: tuistManifestSignature)

        // When
        let manifests = subject
            .locateProjectManifests(at: try temporaryPath(), excluding: [], onlyCurrentDirectory: false)
            .sorted(by: { $0.path < $1.path })

        // Then
        XCTAssertEqual(
            manifests,
            [
                ManifestFilesLocator.ProjectManifest(
                    manifest: .project,
                    path: paths[0]
                ),
                ManifestFilesLocator.ProjectManifest(
                    manifest: .workspace,
                    path: paths[1]
                ),
                ManifestFilesLocator.ProjectManifest(
                    manifest: .project,
                    path: paths[2]
                ),
            ]
        )
    }

    func test_locateProjectManifests_excludes_paths() throws {
        // Given
        let tuistManifestSignature = "import ProjectDescription"
        let paths = try createFiles([
            "A/Project.swift",
            "B/Workspace.swift",
            "C/Project.swift",
            "DirName/ExcludeMe/D/Project.swift",
            "ExcludeMe/Workspace.swift",
        ], content: tuistManifestSignature)
        let excluding = [
            "**/ExcludeMe/**",
        ]

        // When
        let manifests = subject
            .locateProjectManifests(at: try temporaryPath(), excluding: excluding, onlyCurrentDirectory: false)
            .sorted(by: { $0.path < $1.path })

        // Then
        XCTAssertEqual(
            manifests,
            [
                ManifestFilesLocator.ProjectManifest(
                    manifest: .project,
                    path: paths[0]
                ),
                ManifestFilesLocator.ProjectManifest(
                    manifest: .workspace,
                    path: paths[1]
                ),
                ManifestFilesLocator.ProjectManifest(
                    manifest: .project,
                    path: paths[2]
                ),
            ]
        )
    }

    func test_locateProjectManifests_excludes_paths_when_fell_back_to_locatingPath_given_no_root_path() throws {
        // Given
        let tuistManifestSignature = "import ProjectDescription"
        let paths = try createFiles([
            "A/Project.swift",
            "B/Workspace.swift",
            "C/Project.swift",
            "DirName/ExcludeMe/D/Project.swift",
            "ExcludeMe/Workspace.swift",
        ], content: tuistManifestSignature)
        let excluding = [
            "**/ExcludeMe/**",
        ]

        // When
        let manifests = subject
            .locateProjectManifests(at: try temporaryPath(), excluding: excluding, onlyCurrentDirectory: false)
            .sorted(by: { $0.path < $1.path })

        // Then
        XCTAssertEqual(
            manifests,
            [
                ManifestFilesLocator.ProjectManifest(
                    manifest: .project,
                    path: paths[0]
                ),
                ManifestFilesLocator.ProjectManifest(
                    manifest: .workspace,
                    path: paths[1]
                ),
                ManifestFilesLocator.ProjectManifest(
                    manifest: .project,
                    path: paths[2]
                ),
            ]
        )
    }

    func test_locatePluginManifests_returns_all_plugins_when_given_root_path() throws {
        // Given
        let tuistManifestSignature = "import ProjectDescription"
        let paths = try createFiles([
            "Plugin.swift",
            "A/Plugin.swift",
            "B/Plugin.swift",
            "B/C/Plugin.swift",
        ], content: tuistManifestSignature)

        // When
        let manifests = subject
            .locatePluginManifests(
                at: paths[0], // Plugin.swift
                excluding: [],
                onlyCurrentDirectory: false
            )
            .sorted()

        // Then
        XCTAssertEqual(
            manifests,
            [
                paths[1], // A/Plugin.swift
                paths[3], // B/C/Plugin.swift
                paths[2], // B/Plugin.swift
                paths[0], // Plugin.swift
            ]
        )
    }

    func test_locatePluginManifests_returns_only_plugin_in_cwdir_when_only_current_directory() throws {
        // Given
        let paths = try createFiles([
            "Plugin.swift",
            "A/Plugin.swift",
            "B/Plugin.swift",
            "B/C/Plugin.swift",
        ])

        // When
        let manifests = subject.locatePluginManifests(
            at: paths[0].parentDirectory, // Plugin.swift's parent directory
            excluding: [],
            onlyCurrentDirectory: true
        )

        // Then
        XCTAssertEqual(
            manifests,
            [
                paths[0], // Plugin.swift
            ]
        )
    }

    func test_locatePluginManifests_returns_plugin_when_given_child_path() throws {
        // Given
        let tuistManifestSignature = "import ProjectDescription"
        let paths = try createFiles([
            "A/Plugin.swift",
            "A/Helpers/Helper.swift",
        ], content: tuistManifestSignature)

        // When
        let manifests = subject.locatePluginManifests(
            at: paths[1], // A/Helpers/Helper.swift
            excluding: [],
            onlyCurrentDirectory: false
        )

        // Then
        XCTAssertEqual(manifests[0], paths[0]) // A/Plugin.swift
    }

    func test_locatePluginManifests_falls_back_to_locatingPath_when_no_root_path() throws {
        // Given
        let tuistManifestSignature = "import ProjectDescription"
        let paths = try createFiles([
            "A/Plugin.swift",
            "B/Plugin.swift",
        ], content: tuistManifestSignature)

        // When
        let manifests = subject
            .locatePluginManifests(
                at: try temporaryPath(),
                excluding: [],
                onlyCurrentDirectory: false
            )
            .sorted()

        // Then
        XCTAssertEqual(
            manifests,
            [
                paths[0],
                paths[1],
            ]
        )
    }

    func test_locatePluginManifests_excludes_paths() throws {
        // Given
        let tuistManifestSignature = "import ProjectDescription"
        let paths = try createFiles([
            "Plugin.swift",
            "A/Plugin.swift",
            "B/Plugin.swift",
            "B/C/Plugin.swift",
            "DirName/ExcludeMe/D/Plugin.swift",
            "ExcludeMe/Plugin.swift",
        ], content: tuistManifestSignature)
        let excluding = [
            "**/ExcludeMe/**",
        ]

        // When
        let manifests = subject
            .locatePluginManifests(
                at: paths[0], // Plugin.swift
                excluding: excluding,
                onlyCurrentDirectory: false
            )
            .sorted()

        // Then
        XCTAssertEqual(
            manifests,
            [
                paths[1], // A/Plugin.swift
                paths[3], // B/C/Plugin.swift
                paths[2], // B/Plugin.swift
                paths[0], // Plugin.swift
            ]
        )
    }

    func test_locatePluginManifests_excludes_paths_when_fell_back_to_locatingPath_when_no_root_path() throws {
        // Given
        let tuistManifestSignature = "import ProjectDescription"
        let paths = try createFiles([
            "A/Plugin.swift",
            "B/Plugin.swift",
            "DirName/ExcludeMe/D/Plugin.swift",
            "ExcludeMe/Plugin.swift",
        ], content: tuistManifestSignature)
        let excluding = [
            "**/ExcludeMe/**",
        ]

        // When
        let manifests = subject
            .locatePluginManifests(
                at: try temporaryPath(),
                excluding: excluding,
                onlyCurrentDirectory: false
            )
            .sorted()

        // Then
        XCTAssertEqual(
            manifests,
            [
                paths[0],
                paths[1],
            ]
        )
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

    func test_locateProjectManifests_returns_all_manifest_containing_manifest_signature() throws {
        // Given
        let tuistManifestSignature = "import ProjectDescription"
        let correctPaths = try createFiles([
            "Module/Project.swift",
        ], content: tuistManifestSignature)

        // When
        let correctManifest = subject
            .locateProjectManifests(at: try temporaryPath(), excluding: [], onlyCurrentDirectory: false)
            .first

        // Then
        XCTAssertEqual(
            correctManifest,
            ManifestFilesLocator.ProjectManifest(
                manifest: .project,
                path: correctPaths[0]
            )
        )
    }

    func test_locateProjectManifests_returns_all_manifest_containing_empty_files() throws {
        // Given
        let correctPaths = try createFiles([
            "Module/Project.swift",
        ], content: "")

        // When
        let correctManifest = subject
            .locateProjectManifests(at: try temporaryPath(), excluding: [], onlyCurrentDirectory: false)
            .first

        // Then
        XCTAssertEqual(
            correctManifest,
            ManifestFilesLocator.ProjectManifest(
                manifest: .project,
                path: correctPaths[0]
            )
        )
    }

    func test_locateProjectManifests_returns_no_manifest_containing_no_manifest_signature() throws {
        // Given
        try createFiles([
            "Incorrect/Project.swift",
        ], content: "import AnythingElse")

        // When

        let incorrectManifest = subject
            .locateProjectManifests(at: try temporaryPath(), excluding: [], onlyCurrentDirectory: false)
            .first

        // Then
        XCTAssertNil(incorrectManifest)
    }
}
