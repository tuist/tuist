import Foundation
import MockableTest
import ProjectDescription
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class RecursiveManifestLoaderTests: TuistUnitTestCase {
    private var path: AbsolutePath!
    private var manifestLoader: MockManifestLoader!
    private var packageInfoMapper: MockPackageInfoMapping!
    private var projectManifests: [AbsolutePath: Project] = [:]
    private var workspaceManifests: [AbsolutePath: Workspace] = [:]
    private var packageManifests: [AbsolutePath: PackageInfo] = [:]

    private var subject: RecursiveManifestLoader!

    override func setUp() {
        super.setUp()
        do {
            path = try temporaryPath()
        } catch {
            XCTFail("Could not create temporary path.")
        }

        manifestLoader = createManifestLoader()
        packageInfoMapper = MockPackageInfoMapping()
        subject = RecursiveManifestLoader(
            manifestLoader: manifestLoader,
            fileHandler: fileHandler,
            packageInfoMapper: packageInfoMapper
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

    func test_loadProject_loadingSingleProject() throws {
        // Given
        let projectA = createProject(name: "ProjectA")
        try stub(manifest: projectA, at: try RelativePath(validating: "Some/Path/A"))

        // When
        let manifests = try subject.loadWorkspace(
            at: path.appending(try RelativePath(validating: "Some/Path/A")),
            packageSettings: nil
        )

        // Then
        XCTAssertEqual(withRelativePaths(manifests.projects), [
            "Some/Path/A": projectA,
        ])
    }

    func test_loadProject_projectWithDependencies() throws {
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
        try stub(manifest: projectA, at: try RelativePath(validating: "Some/Path/A"))
        try stub(manifest: projectB, at: try RelativePath(validating: "Some/Path/B"))
        try stub(manifest: projectC, at: try RelativePath(validating: "Some/Path/C"))

        // When
        let manifests = try subject.loadWorkspace(
            at: path.appending(try RelativePath(validating: "Some/Path/A")),
            packageSettings: nil
        )

        // Then
        XCTAssertEqual(withRelativePaths(manifests.projects), [
            "Some/Path/A": projectA,
            "Some/Path/B": projectB,
            "Some/Path/C": projectC,
        ])
    }

    func test_loadProject_projectWithTransitiveDependencies() throws {
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
        try stub(manifest: projectA, at: try RelativePath(validating: "Some/Path/A"))
        try stub(manifest: projectB, at: try RelativePath(validating: "Some/Path/B"))
        try stub(manifest: projectC, at: try RelativePath(validating: "Some/Path/C"))
        try stub(manifest: projectD, at: try RelativePath(validating: "Some/Path/D"))
        try stub(manifest: projectE, at: try RelativePath(validating: "Some/Path/E"))

        // When
        let manifests = try subject.loadWorkspace(
            at: path.appending(try RelativePath(validating: "Some/Path/A")),
            packageSettings: nil
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

    func test_loadProject_missingManifest() throws {
        // Given
        let projectA = createProject(
            name: "ProjectA",
            targets: [
                "TargetA": [
                    .project(target: "TargetB", path: "../B"),
                ],
            ]
        )
        try stub(manifest: projectA, at: try RelativePath(validating: "Some/Path/A"))

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.loadWorkspace(
                at: path.appending(try RelativePath(validating: "Some/Path/A")),
                packageSettings: nil
            ),
            ManifestLoaderError.manifestNotFound(.project, path.appending(try RelativePath(validating: "Some/Path/B")))
        )
    }

    func test_loadWorkspace() throws {
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

        try stub(manifest: projectA, at: try RelativePath(validating: "Some/Path/A"))
        try stub(manifest: projectB, at: try RelativePath(validating: "Some/Path/B"))
        try stub(manifest: projectC, at: try RelativePath(validating: "Some/Path/C"))
        try stub(manifest: workspace, at: try RelativePath(validating: "Some/Path"))

        // When
        let manifests = try subject.loadWorkspace(
            at: path.appending(try RelativePath(validating: "Some/Path")),
            packageSettings: nil
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

    func test_loadWorkspace_withGlobPattern() throws {
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

        try stub(manifest: projectA, at: try RelativePath(validating: "Some/Path/A"))
        try stub(manifest: projectB, at: try RelativePath(validating: "Some/Path/B"))
        try stub(manifest: projectC, at: try RelativePath(validating: "Some/Path/C"))
        try stub(manifest: workspace, at: try RelativePath(validating: "Some/Path"))

        // When
        let manifests = try subject.loadWorkspace(
            at: path.appending(try RelativePath(validating: "Some/Path")),
            packageSettings: nil
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

    func test_loadWorkspace_withSameProjectName() throws {
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

        try stub(manifest: projectA, at: try RelativePath(validating: "Some/Path"))
        try stub(manifest: workspace, at: try RelativePath(validating: "Some/Path"))

        // When
        let manifests = try subject.loadWorkspace(
            at: path.appending(try RelativePath(validating: "Some/Path")),
            packageSettings: nil
        )

        // Then
        XCTAssertEqual(manifests.path, path.appending(try RelativePath(validating: "Some/Path")))
        XCTAssertEqual(manifests.workspace, workspace)
        XCTAssertEqual(withRelativePaths(manifests.projects), [
            "Some/Path": projectA,
        ])
    }

    func test_loadSPM_Package() throws {
        // Given
        let packageA = createPackage(name: "PackageA")
        try stub(manifest: packageA, at: try RelativePath(validating: "Some/Path/A"))
        given(packageInfoMapper).map(
            packageInfo: .value(packageA),
            path: .any,
            packageType: .any,
            packageSettings: .any,
            packageToProject: .any
        )
        .willReturn(
            .test(name: "PackageA")
        )

        // When
        let manifests = try subject.loadWorkspace(
            at: path.appending(try RelativePath(validating: "Some/Path/A")),
            packageSettings: .test()
        )

        // Then
        XCTAssertEqual(withRelativePaths(manifests.projects), [
            "Some/Path/A": .test(name: "PackageA"),
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

    private func createPackage(
        name: String
    ) -> PackageInfo {
        return .test(name: name)
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
    ) throws {
        let manifestPath = path
            .appending(relativePath)
            .appending(component: Manifest.project.fileName(path.appending(relativePath)))
        try fileHandler.touch(manifestPath)
        projectManifests[manifestPath.parentDirectory] = manifest
    }

    private func stub(
        manifest: Workspace,
        at relativePath: RelativePath
    ) throws {
        let manifestPath = path
            .appending(relativePath)
            .appending(component: Manifest.workspace.fileName(path.appending(relativePath)))
        try fileHandler.touch(manifestPath)
        workspaceManifests[manifestPath.parentDirectory] = manifest
    }

    private func stub(
        manifest: PackageInfo,
        at relativePath: RelativePath
    ) throws {
        let manifestPath = path
            .appending(relativePath)
            .appending(component: Manifest.package.fileName(path.appending(relativePath)))
        try fileHandler.touch(manifestPath)
        packageManifests[manifestPath.parentDirectory] = manifest
    }

    private func createManifestLoader() -> MockManifestLoader {
        let manifestLoader = MockManifestLoader()
        manifestLoader.loadProjectStub = { [unowned self] path in
            guard let manifest = projectManifests[path] else {
                throw ManifestLoaderError.manifestNotFound(.project, path)
            }
            return manifest
        }

        manifestLoader.loadWorkspaceStub = { [unowned self] path in
            guard let manifest = workspaceManifests[path] else {
                throw ManifestLoaderError.manifestNotFound(.workspace, path)
            }
            return manifest
        }

        manifestLoader.loadPackageStub = { [unowned self] path in
            guard let manifest = packageManifests[path] else {
                throw ManifestLoaderError.manifestNotFound(.workspace, path)
            }
            return manifest
        }

        manifestLoader.manifestsAtStub = { [unowned self] path in
            var manifests = Set<Manifest>()
            if let _ = projectManifests[path] {
                manifests.insert(.project)
            }
            if let _ = workspaceManifests[path] {
                manifests.insert(.workspace)
            }
            if let _ = packageManifests[path] {
                manifests.insert(.package)
            }
            return manifests
        }
        return manifestLoader
    }
}
