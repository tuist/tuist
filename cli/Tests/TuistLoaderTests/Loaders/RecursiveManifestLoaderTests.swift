import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import ProjectDescription
import Testing
import TuistCore
import TuistRootDirectoryLocator
import TuistSupport
import struct XcodeGraph.PackageInfo

@testable import TuistLoader
@testable import TuistTesting

struct RecursiveManifestLoaderTests {
    private let path: AbsolutePath
    private var manifestLoader: MockManifestLoading
    private let packageInfoMapper: MockPackageInfoMapping
    private var projectManifests: [AbsolutePath: Project] = [:]
    private var workspaceManifests: [AbsolutePath: Workspace] = [:]
    private var packageManifests: [AbsolutePath: PackageInfo] = [:]
    private let subject: RecursiveManifestLoader
    private let rootDirectoryLocator: MockRootDirectoryLocating
    private let fileSystem = FileSystem()
    private let fileHandler = FileHandler.shared

    init() throws {
        path = try #require(FileSystem.temporaryTestDirectory)
        packageInfoMapper = MockPackageInfoMapping()
        rootDirectoryLocator = MockRootDirectoryLocating()

        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(path)

        manifestLoader = MockManifestLoading()
        given(manifestLoader)
            .loadProject(at: .any, disableSandbox: .any)
            .willProduce { [self] loadPath, _ in
                guard let manifest = projectManifests[loadPath] else {
                    throw ManifestLoaderError.manifestNotFound(.project, loadPath)
                }
                return manifest
            }
        given(manifestLoader)
            .loadWorkspace(at: .any, disableSandbox: .any)
            .willProduce { [self] loadPath, _ in
                guard let manifest = workspaceManifests[loadPath] else {
                    throw ManifestLoaderError.manifestNotFound(.workspace, loadPath)
                }
                return manifest
            }
        given(manifestLoader)
            .loadPackage(at: .any, disableSandbox: .value(false))
            .willProduce { [self] loadPath, _ in
                guard let manifest = packageManifests[loadPath] else {
                    throw ManifestLoaderError.manifestNotFound(.workspace, loadPath)
                }
                return manifest
            }
        given(manifestLoader)
            .manifests(at: .any)
            .willProduce { [self] loadPath in
                var manifests = Set<Manifest>()
                if projectManifests[loadPath] != nil { manifests.insert(.project) }
                if workspaceManifests[loadPath] != nil { manifests.insert(.workspace) }
                if packageManifests[loadPath] != nil { manifests.insert(.package) }
                return manifests
            }

        subject = RecursiveManifestLoader(
            manifestLoader: manifestLoader,
            fileHandler: fileHandler,
            packageInfoMapper: packageInfoMapper,
            rootDirectoryLocator: rootDirectoryLocator
        )
    }

    @Test(.inTemporaryDirectory) func loadProject_loadingSingleProject() async throws {
        let projectA = createProject(name: "ProjectA")
        try await stub(manifest: projectA, at: try RelativePath(validating: "Some/Path/A"))

        let manifests = try await subject.loadWorkspace(
            at: path.appending(try RelativePath(validating: "Some/Path/A")),
            disableSandbox: false
        )

        #expect(withRelativePaths(manifests.projects) == ["Some/Path/A": projectA])
    }

    @Test(.inTemporaryDirectory) func loadProject_projectWithDependencies() async throws {
        let projectA = createProject(name: "ProjectA", targets: ["TargetA": [.project(target: "TargetB", path: "../B"), .project(target: "TargetC", path: "../C")]])
        let projectB = createProject(name: "ProjectB", targets: ["TargetB": []])
        let projectC = createProject(name: "ProjectC", targets: ["TargetC": []])
        try await stub(manifest: projectA, at: try RelativePath(validating: "Some/Path/A"))
        try await stub(manifest: projectB, at: try RelativePath(validating: "Some/Path/B"))
        try await stub(manifest: projectC, at: try RelativePath(validating: "Some/Path/C"))

        let manifests = try await subject.loadWorkspace(
            at: path.appending(try RelativePath(validating: "Some/Path/A")),
            disableSandbox: false
        )

        #expect(withRelativePaths(manifests.projects) == [
            "Some/Path/A": projectA, "Some/Path/B": projectB, "Some/Path/C": projectC,
        ])
    }

    @Test(.inTemporaryDirectory) func loadWorkspace() async throws {
        let workspace = Workspace.test(name: "Workspace", projects: ["A", "B"])
        let projectA = createProject(name: "ProjectA", targets: ["TargetA": []])
        let projectB = createProject(name: "ProjectB", targets: ["TargetB": [.project(target: "TargetC", path: "../C")]])
        let projectC = createProject(name: "ProjectC", targets: ["TargetC": []])

        try await stub(manifest: projectA, at: try RelativePath(validating: "Some/Path/A"))
        try await stub(manifest: projectB, at: try RelativePath(validating: "Some/Path/B"))
        try await stub(manifest: projectC, at: try RelativePath(validating: "Some/Path/C"))
        try stub(workspace: workspace, at: try RelativePath(validating: "Some/Path"))

        let manifests = try await subject.loadWorkspace(
            at: path.appending(try RelativePath(validating: "Some/Path")),
            disableSandbox: false
        )

        #expect(manifests.path == path.appending(try RelativePath(validating: "Some/Path")))
        #expect(manifests.workspace == workspace)
        #expect(withRelativePaths(manifests.projects) == [
            "Some/Path/A": projectA, "Some/Path/B": projectB, "Some/Path/C": projectC,
        ])
    }

    private func createProject(name: String, targets: [String: [TargetDependency]] = [:]) -> Project {
        let targets: [Target] = targets.map { Target.test(name: $0.key, dependencies: $0.value) }
        return .test(name: name, targets: targets)
    }

    private func withRelativePaths(_ projects: [AbsolutePath: Project]) -> [String: Project] {
        Dictionary(uniqueKeysWithValues: projects.map { ($0.key.relative(to: path).pathString, $0.value) })
    }

    private mutating func stub(manifest: Project, at relativePath: RelativePath) async throws {
        let manifestPath = path.appending(relativePath).appending(component: Manifest.project.fileName(path.appending(relativePath)))
        try await fileSystem.makeDirectory(at: manifestPath.parentDirectory)
        try await fileSystem.touch(manifestPath)
        projectManifests[manifestPath.parentDirectory] = manifest
    }

    private mutating func stub(workspace manifest: Workspace, at relativePath: RelativePath) throws {
        let manifestPath = path.appending(relativePath).appending(component: Manifest.workspace.fileName(path.appending(relativePath)))
        try fileHandler.touch(manifestPath)
        workspaceManifests[manifestPath.parentDirectory] = manifest
    }
}
