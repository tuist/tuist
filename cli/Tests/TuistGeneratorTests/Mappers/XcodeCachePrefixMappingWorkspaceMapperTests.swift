import Foundation
import Mockable
import Path
import Testing
import struct TSCUtility.Version
import TuistConfig
import TuistConstants
import TuistCore
import TuistRootDirectoryLocator
import TuistSupport
import TuistTesting
import XcodeGraph
@testable import TuistGenerator

struct XcodeCachePrefixMappingWorkspaceMapperTests {
    private let repository = try! AbsolutePath(validating: "/Users/dev/app") // swiftlint:disable:this force_try

    private var scratchDirectory: AbsolutePath {
        repository.appending(components: "Tuist", ".build")
    }

    private func stubXcodeVersion(_ version: Version) throws {
        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selectedVersion()
            .willReturn(version)
    }

    /// `rootDirectory` is what the root directory locator finds from the workspace path.
    private func makeSubject(
        enableCaching: Bool = true,
        rootDirectory: AbsolutePath?
    ) -> XcodeCachePrefixMappingWorkspaceMapper {
        let rootDirectoryLocator = MockRootDirectoryLocating()
        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(rootDirectory)
        return XcodeCachePrefixMappingWorkspaceMapper(
            tuist: Tuist(
                project: .generated(.test(generationOptions: .test(enableCaching: enableCaching))),
                fullHandle: nil,
                inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
                url: Constants.URLs.production
            ),
            rootDirectoryLocator: rootDirectoryLocator
        )
    }

    private func makeSubject(enableCaching: Bool = true) -> XcodeCachePrefixMappingWorkspaceMapper {
        makeSubject(enableCaching: enableCaching, rootDirectory: repository)
    }

    /// A package checked out by SwiftPM, before `ExternalDependencyPathWorkspaceMapper`
    /// moves its generated project to `tuist-derived/Projects/`. Its sources stay in the
    /// checkout, outside the `PROJECT_DIR` that project prefix mapping covers.
    private var externalProject: Project {
        externalProject(scratchDirectory: scratchDirectory)
    }

    private func externalProject(scratchDirectory: AbsolutePath) -> Project {
        let checkout = scratchDirectory.appending(components: "checkouts", "swift-atomics")
        return Project.test(
            path: checkout,
            sourceRootPath: checkout,
            xcodeProjPath: checkout.appending(component: "swift-atomics.xcodeproj"),
            name: "swift-atomics",
            type: .external(hash: nil),
            swiftPackageManagerScratchDirectory: scratchDirectory
        )
    }

    private var appProject: Project {
        let path = repository.appending(component: "App")
        return Project.test(
            path: path,
            sourceRootPath: path,
            xcodeProjPath: path.appending(component: "App.xcodeproj"),
            name: "App"
        )
    }

    private var workspace: Workspace {
        Workspace.test(path: repository, xcWorkspacePath: repository.appending(component: "App.xcworkspace"))
    }

    private var rootMappings: SettingValue {
        .array([
            "$(inherited)",
            #""$(TUIST_PREFIX_MAPPING_ROOT_DIR)/Tuist/.build=/^spm""#,
            #""$(TUIST_PREFIX_MAPPING_ROOT_DIR)=/^root""#,
        ])
    }

    @Test(.withMockedXcodeController)
    func map_whenXcode27_mapsScratchAndRootDirectoriesInEveryProject() async throws {
        // Given
        try stubXcodeVersion(Version(27, 0, 0))
        let subject = makeSubject()

        // When
        let (mapped, sideEffects) = try await subject.map(
            workspace: WorkspaceWithProjects(workspace: workspace, projects: [appProject, externalProject])
        )

        // Then
        #expect(sideEffects.isEmpty)
        for project in mapped.projects {
            #expect(project.settings.base["TUIST_PREFIX_MAPPING_ROOT_DIR"] == .string("/Users/dev/app"))
            #expect(project.settings.base["SWIFT_OTHER_PREFIX_MAPPINGS"] == rootMappings)
            #expect(project.settings.base["CLANG_OTHER_PREFIX_MAPPINGS"] == rootMappings)
        }
    }

    /// `tuist generate --path App` generates the workspace below the root, while the
    /// scratch directory is still resolved from the root. Anchoring on the root keeps
    /// the scratch mapping relative, so it reads the same in every checkout.
    @Test(.withMockedXcodeController)
    func map_whenWorkspaceIsBelowTheRoot_anchorsOnTheRoot() async throws {
        // Given
        try stubXcodeVersion(Version(27, 0, 0))
        let subject = makeSubject()
        let workspaceDirectory = repository.appending(component: "App")
        let workspace = Workspace.test(
            path: workspaceDirectory,
            xcWorkspacePath: workspaceDirectory.appending(component: "App.xcworkspace")
        )

        // When
        let (mapped, _) = try await subject.map(
            workspace: WorkspaceWithProjects(workspace: workspace, projects: [appProject, externalProject])
        )

        // Then
        for project in mapped.projects {
            #expect(project.settings.base["TUIST_PREFIX_MAPPING_ROOT_DIR"] == .string("/Users/dev/app"))
            #expect(project.settings.base["SWIFT_OTHER_PREFIX_MAPPINGS"] == rootMappings)
        }
    }

    @Test(.withMockedXcodeController)
    func map_whenRootDirectoryIsNotFound_anchorsOnTheWorkspaceDirectory() async throws {
        // Given
        try stubXcodeVersion(Version(27, 0, 0))
        let subject = makeSubject(rootDirectory: nil)

        // When
        let (mapped, _) = try await subject.map(
            workspace: WorkspaceWithProjects(workspace: workspace, projects: [externalProject])
        )

        // Then
        let base = try #require(mapped.projects.first?.settings.base)
        #expect(base["TUIST_PREFIX_MAPPING_ROOT_DIR"] == .string("/Users/dev/app"))
        #expect(base["SWIFT_OTHER_PREFIX_MAPPINGS"] == rootMappings)
    }

    /// Without packages there is no scratch directory to map, but first-party sources
    /// outside their own project directory still need the root mapping.
    @Test(.withMockedXcodeController)
    func map_whenNoExternalProjects_mapsOnlyTheRootDirectory() async throws {
        // Given
        try stubXcodeVersion(Version(27, 0, 0))
        let subject = makeSubject()

        // When
        let (mapped, _) = try await subject.map(
            workspace: WorkspaceWithProjects(workspace: workspace, projects: [appProject])
        )

        // Then
        #expect(
            mapped.projects.first?.settings.base["SWIFT_OTHER_PREFIX_MAPPINGS"]
                == .array(["$(inherited)", #""$(TUIST_PREFIX_MAPPING_ROOT_DIR)=/^root""#])
        )
    }

    @Test(.withMockedXcodeController)
    func map_whenProjectDefinesPrefixMappings_appendsToThem() async throws {
        // Given
        try stubXcodeVersion(Version(27, 0, 0))
        let subject = makeSubject()
        var project = appProject
        project.settings = project.settings.with(base: [
            "SWIFT_OTHER_PREFIX_MAPPINGS": .string("/opt/shared=/^shared"),
        ])

        // When
        let (mapped, _) = try await subject.map(
            workspace: WorkspaceWithProjects(workspace: workspace, projects: [project])
        )

        // Then
        #expect(
            mapped.projects.first?.settings.base["SWIFT_OTHER_PREFIX_MAPPINGS"]
                == .array(["/opt/shared=/^shared", #""$(TUIST_PREFIX_MAPPING_ROOT_DIR)=/^root""#])
        )
    }

    /// Xcode splits a list element at spaces, so a root path with spaces stays in the
    /// plain root directory setting, out of the mapping elements.
    @Test(.withMockedXcodeController)
    func map_whenRootDirectoryHasSpaces_keepsItOutOfTheMappings() async throws {
        // Given
        try stubXcodeVersion(Version(27, 0, 0))
        let repository = try AbsolutePath(validating: "/Users/dev/my app")
        let subject = makeSubject(rootDirectory: repository)
        let workspace = Workspace.test(path: repository, xcWorkspacePath: repository.appending(component: "App.xcworkspace"))
        let project = externalProject(scratchDirectory: repository.appending(components: "Tuist", ".build"))

        // When
        let (mapped, _) = try await subject.map(
            workspace: WorkspaceWithProjects(workspace: workspace, projects: [project])
        )

        // Then
        let base = try #require(mapped.projects.first?.settings.base)
        #expect(base["TUIST_PREFIX_MAPPING_ROOT_DIR"] == .string("/Users/dev/my app"))
        #expect(base["SWIFT_OTHER_PREFIX_MAPPINGS"] == rootMappings)
    }

    /// A scratch directory outside the root is written as an absolute path, quoted and
    /// escaped so that spaces and quotes stay inside a single mapping.
    @Test(.withMockedXcodeController)
    func map_whenScratchDirectoryIsOutsideTheRoot_quotesItsAbsolutePath() async throws {
        // Given
        try stubXcodeVersion(Version(27, 0, 0))
        let subject = makeSubject()
        let project = try externalProject(scratchDirectory: AbsolutePath(validating: #"/Volumes/Shared Cache/say "hi"/.build"#))

        // When
        let (mapped, _) = try await subject.map(
            workspace: WorkspaceWithProjects(workspace: workspace, projects: [project])
        )

        // Then
        #expect(
            mapped.projects.first?.settings.base["CLANG_OTHER_PREFIX_MAPPINGS"] == .array([
                "$(inherited)",
                #""/Volumes/Shared Cache/say \"hi\"/.build=/^spm""#,
                #""$(TUIST_PREFIX_MAPPING_ROOT_DIR)=/^root""#,
            ])
        )
    }

    /// Earlier Xcodes don't implement prefix mapping, so the settings would be inert.
    @Test(.withMockedXcodeController)
    func map_whenXcodeOlderThan27_returnsUnmodifiedWorkspace() async throws {
        // Given
        try stubXcodeVersion(Version(26, 5, 0))
        let subject = makeSubject()
        let workspaceWithProjects = WorkspaceWithProjects(workspace: workspace, projects: [appProject, externalProject])

        // When
        let (mapped, _) = try await subject.map(workspace: workspaceWithProjects)

        // Then
        #expect(mapped == workspaceWithProjects)
    }

    @Test(.withMockedXcodeController)
    func map_whenCachingDisabled_returnsUnmodifiedWorkspace() async throws {
        // Given
        try stubXcodeVersion(Version(27, 0, 0))
        let subject = makeSubject(enableCaching: false)
        let workspaceWithProjects = WorkspaceWithProjects(workspace: workspace, projects: [appProject, externalProject])

        // When
        let (mapped, _) = try await subject.map(workspace: workspaceWithProjects)

        // Then
        #expect(mapped == workspaceWithProjects)
    }
}
