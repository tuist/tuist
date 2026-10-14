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
import XCTest

@testable import TuistLoader
@testable import TuistTesting

final class RecursiveManifestLoaderTests: TuistUnitTestCase {
    private var path: AbsolutePath!
    private var manifestLoader: MockManifestLoading!
    private var packageInfoMapper: MockPackageInfoMapping!
    private var projectManifests: [AbsolutePath: Project] = [:]
    private var workspaceManifests: [AbsolutePath: Workspace] = [:]

    private var subject: RecursiveManifestLoader!
    private var rootDirectoryLocator: MockRootDirectoryLocating!

    override func setUpWithError() throws {
        super.setUp()
        do {
            path = try temporaryPath()
        } catch {
            XCTFail("Could not create temporary path.")
        }

        manifestLoader = createManifestLoader()
        packageInfoMapper = MockPackageInfoMapping()
        rootDirectoryLocator = MockRootDirectoryLocating()

        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(try temporaryPath())

        subject = RecursiveManifestLoader(
            manifestLoader: manifestLoader,
            packageInfoMapper: packageInfoMapper,
            rootDirectoryLocator: rootDirectoryLocator
        )
    }

    override func tearDown() {
        path = nil
        manifestLoader = nil
        packageInfoMapper = nil
        subject = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_loadProject_loadingSingleProject() async throws {
        // Given
        let projectA = createProject(name: "ProjectA")
        try await stub(manifest: projectA, at: try RelativePath(validating: "Some/Path/A"))

        // When
        let manifests = try await subject.loadWorkspace(
            at: path.appending(try RelativePath(validating: "Some/Path/A")),
            disableSandbox: false
        )

        // Then
        XCTAssertEqual(withRelativePaths(manifests.projects), [
            "Some/Path/A": projectA,
        ])
    }

    func test_loadProject_projectWithDependencies() async throws {
        // Given
        let projectA = createProject(
            name: "ProjectA",
            targets: [
                "TargetA": [
                    .project(target: "TargetB", path: "../B"),
                    .project(target: "TargetC", path: "../C"),
                ],
            ]
        )
        let projectB = createProject(
            name: "ProjectB",
            targets: [
                "TargetB": [],
            ]
        )
        let projectC = createProject(
            name: "ProjectC",
            targets: [
                "TargetC": [],
            ]
        )
        try await stub(manifest: projectA, at: try RelativePath(validating: "Some/Path/A"))
        try await stub(manifest: projectB, at: try RelativePath(validating: "Some/Path/B"))
        try await stub(manifest: projectC, at: try RelativePath(validating: "Some/Path/C"))

        // When
        let manifests = try await subject.loadWorkspace(
            at: path.appending(try RelativePath(validating: "Some/Path/A")),
            disableSandbox: false
        )

        // Then
        XCTAssertEqual(withRelativePaths(manifests.projects), [
            "Some/Path/A": projectA,
            "Some/Path/B": projectB,
            "Some/Path/C": projectC,
        ])
    }

    func test_loadProject_projectWithTransitiveDependencies() async throws {
        // Given
        let projectA = createProject(
            name: "ProjectA",
            targets: [
                "TargetA": [.project(target: "TargetB", path: "../B")],
            ]
        )
        let projectB = createProject(
            name: "ProjectB",
            targets: [
                "TargetB": [.project(target: "TargetC", path: "../C")],
            ]
        )
        let projectC = createProject(
            name: "ProjectC",
            targets: [
                "TargetC": [
                    .project(target: "TargetD", path: "../D"),
                    .project(target: "TargetE", path: "../E"),
                ],
            ]
        )
        let projectD = createProject(
            name: "ProjectD",
            targets: [
                "TargetD": [],
            ]
        )
        let projectE = createProject(
            name: "ProjectE",
            targets: [
                "TargetE": [],
            ]
        )
        try await stub(manifest: projectA, at: try RelativePath(validating: "Some/Path/A"))
        try await stub(manifest: projectB, at: try RelativePath(validating: "Some/Path/B"))
        try await stub(manifest: projectC, at: try RelativePath(validating: "Some/Path/C"))
        try await stub(manifest: projectD, at: try RelativePath(validating: "Some/Path/D"))
        try await stub(manifest: projectE, at: try RelativePath(validating: "Some/Path/E"))

        // When
        let manifests = try await subject.loadWorkspace(
            at: path.appending(try RelativePath(validating: "Some/Path/A")),
            disableSandbox: false
        )

        // Then
        XCTAssertEqual(withRelativePaths(manifests.projects), [
            "Some/Path/A": projectA,
            "Some/Path/B": projectB,
            "Some/Path/C": projectC,
            "Some/Path/D": projectD,
            "Some/Path/E": projectE,
        ])
    }

    func test_loadProject_missingManifest() async throws {
        // Given
        let projectA = createProject(
            name: "ProjectA",
            targets: [
                "TargetA": [
                    .project(target: "TargetB", path: "../B"),
                ],
            ]
        )
        try await stub(manifest: projectA, at: try RelativePath(validating: "Some/Path/A"))

        // When / Then
        await XCTAssertThrowsSpecific(
            { try await self.subject.loadWorkspace(
                at: self.path.appending(try RelativePath(validating: "Some/Path/A")),
                disableSandbox: false
            ) },
            ManifestLoaderError.manifestNotFound(.project, path.appending(try RelativePath(validating: "Some/Path/B")))
        )
    }

    func test_loadWorkspace() async throws {
        // Given
        let workspace = Workspace.test(
            name: "Workspace",
            projects: [
                "A",
                "B",
            ]
        )

        let projectA = createProject(
            name: "ProjectA",
            targets: [
                "TargetA": [],
            ]
        )
        let projectB = createProject(
            name: "ProjectB",
            targets: [
                "TargetB": [.project(target: "TargetC", path: "../C")],
            ]
        )
        let projectC = createProject(
            name: "ProjectC",
            targets: [
                "TargetC": [],
            ]
        )

        try await stub(manifest: projectA, at: try RelativePath(validating: "Some/Path/A"))
        try await stub(manifest: projectB, at: try RelativePath(validating: "Some/Path/B"))
        try await stub(manifest: projectC, at: try RelativePath(validating: "Some/Path/C"))
        try await stub(manifest: workspace, at: try RelativePath(validating: "Some/Path"))

        // When
        let manifests = try await subject.loadWorkspace(
            at: path.appending(try RelativePath(validating: "Some/Path")),
            disableSandbox: false
        )

        // Then
        XCTAssertEqual(manifests.path, path.appending(try RelativePath(validating: "Some/Path")))
        XCTAssertEqual(manifests.workspace, workspace)
        XCTAssertEqual(withRelativePaths(manifests.projects), [
            "Some/Path/A": projectA,
            "Some/Path/B": projectB,
            "Some/Path/C": projectC,
        ])
    }

    func test_loadWorkspace_withGlobPattern() async throws {
        // Given
        let workspace = Workspace.test(
            name: "Workspace",
            projects: [
                "*",
            ]
        )

        let projectA = createProject(
            name: "ProjectA",
            targets: [
                "TargetA": [],
            ]
        )
        let projectB = createProject(
            name: "ProjectB",
            targets: [
                "TargetB": [.project(target: "TargetC", path: "../C")],
            ]
        )
        let projectC = createProject(
            name: "ProjectC",
            targets: [
                "TargetC": [],
            ]
        )

        try await stub(manifest: projectA, at: try RelativePath(validating: "Some/Path/A"))
        try await stub(manifest: projectB, at: try RelativePath(validating: "Some/Path/B"))
        try await stub(manifest: projectC, at: try RelativePath(validating: "Some/Path/C"))
        try await stub(manifest: workspace, at: try RelativePath(validating: "Some/Path"))

        // When
        let manifests = try await subject.loadWorkspace(
            at: path.appending(try RelativePath(validating: "Some/Path")),
            disableSandbox: false
        )

        // Then
        XCTAssertEqual(manifests.path, path.appending(try RelativePath(validating: "Some/Path")))
        XCTAssertEqual(manifests.workspace, workspace)
        XCTAssertEqual(withRelativePaths(manifests.projects), [
            "Some/Path/A": projectA,
            "Some/Path/B": projectB,
            "Some/Path/C": projectC,
        ])
    }

    func test_loadWorkspace_withSameProjectName() async throws {
        // Given
        let workspace = Workspace.test(
            name: "MyWorkspace",
            projects: [
                ".",
            ],
            schemes: [
                .scheme(name: "CustomWorkspaceScheme"),
            ]
        )

        let projectA = createProject(
            name: "ProjectA",
            targets: [
                "TargetA": [],
            ]
        )

        try await stub(manifest: projectA, at: try RelativePath(validating: "Some/Path"))
        try await stub(manifest: workspace, at: try RelativePath(validating: "Some/Path"))

        // When
        let manifests = try await subject.loadWorkspace(
            at: path.appending(try RelativePath(validating: "Some/Path")),
            disableSandbox: false
        )

        // Then
        XCTAssertEqual(manifests.path, path.appending(try RelativePath(validating: "Some/Path")))
        XCTAssertEqual(manifests.workspace, workspace)
        XCTAssertEqual(withRelativePaths(manifests.projects), [
            "Some/Path": projectA,
        ])
    }

    // MARK: - Helpers

    private func createProject(
        name: String,
        targets: [String: [TargetDependency]] = [:]
    ) -> Project {
        let targets: [Target] = targets.map {
            Target.test(name: $0.key, dependencies: $0.value)
        }
        return .test(name: name, targets: targets)
    }

    private func withRelativePaths(_ projects: [AbsolutePath: Project]) -> [String: Project] {
        Dictionary(uniqueKeysWithValues: projects.map {
            ($0.key.relative(to: path).pathString, $0.value)
        })
    }

    private func stub(
        manifest: Project,
        at path: AbsolutePath
    ) {
        projectManifests[path] = manifest
    }

    private func stub(
        manifest: Workspace,
        at path: AbsolutePath
    ) {
        workspaceManifests[path] = manifest
    }

    private func stub(
        manifest: Project,
        at relativePath: RelativePath
    ) async throws {
        let manifestPath = path
            .appending(relativePath)
            .appending(component: Manifest.project.fileName(path.appending(relativePath)))
        try await fileSystem.makeDirectory(at: manifestPath.parentDirectory)
        try await fileSystem.touch(manifestPath)
        projectManifests[manifestPath.parentDirectory] = manifest
    }

    private func stub(
        manifest: Workspace,
        at relativePath: RelativePath
    ) async throws {
        let manifestPath = path
            .appending(relativePath)
            .appending(component: Manifest.workspace.fileName(path.appending(relativePath)))
        try await fileSystem.makeDirectory(at: manifestPath.parentDirectory)
        try await fileSystem.touch(manifestPath)
        workspaceManifests[manifestPath.parentDirectory] = manifest
    }

    private func createManifestLoader() -> MockManifestLoading {
        let manifestLoader = MockManifestLoading()
        given(manifestLoader)
            .loadProject(at: .any, disableSandbox: .any)
            .willProduce { [unowned self] path, _ in
                guard let manifest = projectManifests[path] else {
                    throw ManifestLoaderError.manifestNotFound(.project, path)
                }
                return manifest
            }

        given(manifestLoader)
            .loadWorkspace(at: .any, disableSandbox: .any)
            .willProduce { [unowned self] path, _ in
                guard let manifest = workspaceManifests[path] else {
                    throw ManifestLoaderError.manifestNotFound(.workspace, path)
                }
                return manifest
            }

        given(manifestLoader)
            .manifests(at: .any)
            .willProduce { [unowned self] path in
                var manifests = Set<Manifest>()
                if let _ = projectManifests[path] {
                    manifests.insert(.project)
                }
                if let _ = workspaceManifests[path] {
                    manifests.insert(.workspace)
                }
                return manifests
            }
        return manifestLoader
    }
}

struct RecursiveManifestLoaderSwiftPackageTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory)
    func loadSPM_Package() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let packageA = PackageInfo.test(name: "PackageA")
        let packageAPath = try await stubPackage(at: "Some/Path/A", in: temporaryDirectory)
        let packageInfoMapper = makePackageInfoMapper(returning: .test(name: "PackageA"), for: packageA)
        let subject = makeSubject(
            packageManifests: [packageAPath: packageA],
            packageInfoMapper: packageInfoMapper,
            temporaryDirectory: temporaryDirectory
        )

        // When
        var manifests = try await subject.loadWorkspace(at: packageAPath, disableSandbox: false)
        manifests = try await subject.loadAndMergePackageProjects(
            in: manifests,
            packageSettings: .test(),
            disableSandbox: false
        )

        // Then
        #expect(relativePaths(manifests.projects, to: temporaryDirectory) == [
            "Some/Path/A": .test(name: "PackageA"),
        ])
    }

    @Test(.inTemporaryDirectory)
    func loadSPM_Package_ignoresPackagesInCustomSwiftPMCheckouts() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let packageA = PackageInfo.test(name: "PackageA")
        let checkoutPackage = PackageInfo.test(name: "CheckoutPackage")
        let packageAPath = try await stubPackage(at: "Some/Path/A", in: temporaryDirectory)
        let checkoutPackagePath = try await stubPackage(
            at: "Some/Path/A/custom-build/checkouts/CheckoutPackage",
            in: temporaryDirectory
        )
        let packageInfoMapper = makePackageInfoMapper(returning: .test(name: "PackageA"), for: packageA)
        let subject = makeSubject(
            packageManifests: [packageAPath: packageA, checkoutPackagePath: checkoutPackage],
            packageInfoMapper: packageInfoMapper,
            temporaryDirectory: temporaryDirectory
        )

        // When
        var manifests = try await subject.loadWorkspace(at: packageAPath, disableSandbox: false)
        manifests = try await subject.loadAndMergePackageProjects(
            in: manifests,
            packageSettings: .test(),
            disableSandbox: false,
            swiftPackageManagerScratchDirectory: temporaryDirectory.appending(
                try RelativePath(validating: "Some/Path/A/custom-build")
            )
        )

        // Then
        #expect(relativePaths(manifests.projects, to: temporaryDirectory) == [
            "Some/Path/A": .test(name: "PackageA"),
        ])
    }

    @Test(.inTemporaryDirectory)
    func loadSPM_Package_whenPathContainsCheckouts_doesNotFilterItOut() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let packageA = PackageInfo.test(name: "PackageA")
        let packageAPath = try await stubPackage(at: "Some/checkouts/A", in: temporaryDirectory)
        let packageInfoMapper = makePackageInfoMapper(returning: .test(name: "PackageA"), for: packageA)
        let subject = makeSubject(
            packageManifests: [packageAPath: packageA],
            packageInfoMapper: packageInfoMapper,
            temporaryDirectory: temporaryDirectory
        )

        // When
        var manifests = try await subject.loadWorkspace(at: packageAPath, disableSandbox: false)
        manifests = try await subject.loadAndMergePackageProjects(
            in: manifests,
            packageSettings: .test(),
            disableSandbox: false,
            swiftPackageManagerScratchDirectory: temporaryDirectory.appending(
                try RelativePath(validating: "Some/custom-build")
            )
        )

        // Then
        #expect(relativePaths(manifests.projects, to: temporaryDirectory) == [
            "Some/checkouts/A": .test(name: "PackageA"),
        ])
    }

    // MARK: - Helpers

    private func makeSubject(
        packageManifests: [AbsolutePath: PackageInfo],
        packageInfoMapper: MockPackageInfoMapping,
        temporaryDirectory: AbsolutePath
    ) -> RecursiveManifestLoader {
        let manifestLoader = MockManifestLoading()
        given(manifestLoader)
            .loadProject(at: .any, disableSandbox: .any)
            .willProduce { path, _ in
                throw ManifestLoaderError.manifestNotFound(.project, path)
            }
        given(manifestLoader)
            .loadWorkspace(at: .any, disableSandbox: .any)
            .willProduce { path, _ in
                throw ManifestLoaderError.manifestNotFound(.workspace, path)
            }
        given(manifestLoader)
            .loadPackage(at: .any, disableSandbox: .value(false))
            .willProduce { path, _ in
                guard let manifest = packageManifests[path] else {
                    throw ManifestLoaderError.manifestNotFound(.package, path)
                }
                return manifest
            }
        given(manifestLoader)
            .manifests(at: .any)
            .willProduce { path in
                packageManifests[path] == nil ? [] : [.package]
            }

        let rootDirectoryLocator = MockRootDirectoryLocating()
        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(temporaryDirectory)

        return RecursiveManifestLoader(
            manifestLoader: manifestLoader,
            packageInfoMapper: packageInfoMapper,
            rootDirectoryLocator: rootDirectoryLocator
        )
    }

    private func makePackageInfoMapper(returning project: Project, for packageInfo: PackageInfo) -> MockPackageInfoMapping {
        let packageInfoMapper = MockPackageInfoMapping()
        given(packageInfoMapper)
            .map(
                packageInfo: .value(packageInfo),
                path: .any,
                packageType: .any,
                packageSettings: .any,
                packageModuleAliases: .any,
                packageProducts: .any,
                enabledTraits: .any
            )
            .willReturn(project)
        return packageInfoMapper
    }

    private func stubPackage(at relativePath: String, in temporaryDirectory: AbsolutePath) async throws -> AbsolutePath {
        let packagePath = temporaryDirectory.appending(try RelativePath(validating: relativePath))
        try await fileSystem.makeDirectory(at: packagePath)
        try await fileSystem.touch(packagePath.appending(component: Manifest.package.fileName(packagePath)))
        return packagePath
    }

    private func relativePaths(_ projects: [AbsolutePath: Project], to path: AbsolutePath) -> [String: Project] {
        Dictionary(uniqueKeysWithValues: projects.map {
            ($0.key.relative(to: path).pathString, $0.value)
        })
    }
}
