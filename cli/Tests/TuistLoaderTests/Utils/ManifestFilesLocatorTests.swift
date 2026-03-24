import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistConstants
import TuistCore
import TuistRootDirectoryLocator

@testable import TuistLoader
@testable import TuistSupport
@testable import TuistTesting

struct ManifestFilesLocatorTests {
    private let subject: ManifestFilesLocator
    private let rootDirectoryLocator: MockRootDirectoryLocating
    private let fileSystem = FileSystem()

    init() throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        rootDirectoryLocator = MockRootDirectoryLocating()
        given(rootDirectoryLocator).locate(from: .any).willReturn(temporaryPath)
        subject = ManifestFilesLocator(rootDirectoryLocator: rootDirectoryLocator, fileSystem: fileSystem)
    }

    @Test(.inTemporaryDirectory) func locateProjectManifests_returns_all_manifest_no_workspace_given_child_path() async throws {
        let tuistManifestSignature = "import ProjectDescription"
        let paths = try await TuistTest.createFiles(
            ["Module/Project.swift", "Project.swift", Constants.tuistManifestFileName],
            content: tuistManifestSignature
        )
        let manifests = try await subject.locateProjectManifests(at: paths.first!, excluding: [], onlyCurrentDirectory: false)
            .sorted(by: { $0.path < $1.path })
        #expect(manifests == [
            ManifestFilesLocator.ProjectManifest(manifest: .project, path: paths[0]),
            ManifestFilesLocator.ProjectManifest(manifest: .project, path: paths[1]),
        ])
    }

    @Test(.inTemporaryDirectory) func locateProjectManifests_returns_all_manifest_with_workspace_given_child_path() async throws {
        let tuistManifestSignature = "import ProjectDescription"
        let paths = try await TuistTest.createFiles(
            ["Module/Project.swift", "Workspace.swift", Constants.tuistManifestFileName],
            content: tuistManifestSignature
        )
        let manifests = try await subject.locateProjectManifests(at: paths.first!, excluding: [], onlyCurrentDirectory: false)
            .sorted(by: { $0.path < $1.path })
        #expect(manifests == [
            ManifestFilesLocator.ProjectManifest(manifest: .project, path: paths[0]),
            ManifestFilesLocator.ProjectManifest(manifest: .workspace, path: paths[1]),
        ])
    }

    @Test(.inTemporaryDirectory) func locateProjectManifests_returns_only_manifest_in_locating_path_when_only_current_directory(
    ) async throws {
        let paths = try await TuistTest.createFiles(["Workspace.swift", "Module/Project.swift", Constants.tuistManifestFileName])
        let manifests = try await subject.locateProjectManifests(
            at: paths.first!.parentDirectory,
            excluding: [],
            onlyCurrentDirectory: true
        ).sorted(by: { $0.path < $1.path })
        #expect(manifests == [ManifestFilesLocator.ProjectManifest(manifest: Manifest.workspace, path: paths[0])])
    }

    @Test(.inTemporaryDirectory) func locateProjectManifests_falls_back_to_locatingPath_given_no_root_path() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let tuistManifestSignature = "import ProjectDescription"
        let paths = try await TuistTest.createFiles(
            ["A/Project.swift", "B/Workspace.swift", "C/Project.swift"],
            content: tuistManifestSignature
        )
        let manifests = try await subject.locateProjectManifests(at: temporaryPath, excluding: [], onlyCurrentDirectory: false)
            .sorted(by: { $0.path < $1.path })
        #expect(manifests == [
            ManifestFilesLocator.ProjectManifest(manifest: .project, path: paths[0]),
            ManifestFilesLocator.ProjectManifest(manifest: .workspace, path: paths[1]),
            ManifestFilesLocator.ProjectManifest(manifest: .project, path: paths[2]),
        ])
    }

    @Test(.inTemporaryDirectory) func locateProjectManifests_excludes_paths() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let tuistManifestSignature = "import ProjectDescription"
        let paths = try await TuistTest.createFiles(
            [
                "A/Project.swift",
                "B/Workspace.swift",
                "C/Project.swift",
                "DirName/ExcludeMe/D/Project.swift",
                "ExcludeMe/Workspace.swift",
            ],
            content: tuistManifestSignature
        )
        let manifests = try await subject.locateProjectManifests(
            at: temporaryPath,
            excluding: ["**/ExcludeMe/**"],
            onlyCurrentDirectory: false
        ).sorted(by: { $0.path < $1.path })
        #expect(manifests == [
            ManifestFilesLocator.ProjectManifest(manifest: .project, path: paths[0]),
            ManifestFilesLocator.ProjectManifest(manifest: .workspace, path: paths[1]),
            ManifestFilesLocator.ProjectManifest(manifest: .project, path: paths[2]),
        ])
    }

    @Test(.inTemporaryDirectory) func locateConfig() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let paths = try await TuistTest.createFiles(["Module01/File01.swift", "File01.swift", Constants.tuistManifestFileName])
        let configPath = try await subject.locateConfig(at: temporaryPath)
        #expect(configPath != nil)
        #expect(paths.last == configPath)
    }

    @Test(.inTemporaryDirectory) func locateConfig_where_config_not_exist() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.createFiles(["Module01/File01.swift", "File01.swift"])
        let configPath = try await subject.locateConfig(at: temporaryPath)
        #expect(configPath == nil)
    }

    @Test(.inTemporaryDirectory) func locateConfig_where_tuist_file_is_not_a_directory() async throws {
        let paths = try await TuistTest.createFiles(["tuist"])
        let configPath = try await subject.locateConfig(at: paths[0].parentDirectory)
        #expect(configPath == nil)
    }

    @Test(.inTemporaryDirectory) func locatePackageManifest_when_in_root() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let paths = try await TuistTest.createFiles(["File01.swift", Constants.tuistManifestFileName, "Package.swift"])
        let packageManifestPath = try await subject.locatePackageManifest(at: temporaryPath)
        #expect(packageManifestPath != nil)
        #expect(paths.last == packageManifestPath)
    }

    @Test(.inTemporaryDirectory) func locatePackageManifest() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let paths = try await TuistTest.createFiles([
            "File01.swift",
            Constants.tuistManifestFileName,
            "Package.swift",
            "Tuist/Package.swift",
        ])
        let packageManifestPath = try await subject.locatePackageManifest(at: temporaryPath)
        #expect(packageManifestPath != nil)
        #expect(paths.last == packageManifestPath)
    }

    @Test(.inTemporaryDirectory) func locateProjectManifests_returns_all_manifest_containing_manifest_signature() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let tuistManifestSignature = "import ProjectDescription"
        let correctPaths = try await TuistTest.createFiles(["Module/Project.swift"], content: tuistManifestSignature)
        let correctManifest = try await subject.locateProjectManifests(
            at: temporaryPath,
            excluding: [],
            onlyCurrentDirectory: false
        ).first
        #expect(correctManifest == ManifestFilesLocator.ProjectManifest(manifest: .project, path: correctPaths[0]))
    }

    @Test(.inTemporaryDirectory) func locateProjectManifests_returns_all_manifest_containing_empty_files() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let correctPaths = try await TuistTest.createFiles(["Module/Project.swift"], content: "")
        let correctManifest = try await subject.locateProjectManifests(
            at: temporaryPath,
            excluding: [],
            onlyCurrentDirectory: false
        ).first
        #expect(correctManifest == ManifestFilesLocator.ProjectManifest(manifest: .project, path: correctPaths[0]))
    }

    @Test(.inTemporaryDirectory) func locateProjectManifests_returns_no_manifest_containing_no_manifest_signature() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.createFiles(["Incorrect/Project.swift"], content: "import AnythingElse")
        let incorrectManifest = try await subject.locateProjectManifests(
            at: temporaryPath,
            excluding: [],
            onlyCurrentDirectory: false
        ).first
        #expect(incorrectManifest == nil)
    }

    @Test(.inTemporaryDirectory) func locatePluginManifests_returns_all_plugins_when_given_root_path() async throws {
        let tuistManifestSignature = "import ProjectDescription"
        let paths = try await TuistTest.createFiles(
            ["Plugin.swift", "A/Plugin.swift", "B/Plugin.swift", "B/C/Plugin.swift"],
            content: tuistManifestSignature
        )
        let manifests = try await subject.locatePluginManifests(at: paths[0], excluding: [], onlyCurrentDirectory: false).sorted()
        #expect(manifests == [paths[1], paths[3], paths[2], paths[0]])
    }

    @Test(.inTemporaryDirectory) func locatePluginManifests_returns_only_plugin_in_cwdir_when_only_current_directory(
    ) async throws {
        let paths = try await TuistTest.createFiles(["Plugin.swift", "A/Plugin.swift", "B/Plugin.swift", "B/C/Plugin.swift"])
        let manifests = try await subject.locatePluginManifests(
            at: paths[0].parentDirectory,
            excluding: [],
            onlyCurrentDirectory: true
        )
        #expect(manifests == [paths[0]])
    }

    @Test(.inTemporaryDirectory) func locatePluginManifests_returns_plugin_when_given_child_path() async throws {
        let tuistManifestSignature = "import ProjectDescription"
        let paths = try await TuistTest.createFiles(["A/Plugin.swift", "A/Helpers/Helper.swift"], content: tuistManifestSignature)
        let manifests = try await subject.locatePluginManifests(at: paths[1], excluding: [], onlyCurrentDirectory: false)
        #expect(manifests[0] == paths[0])
    }
}
