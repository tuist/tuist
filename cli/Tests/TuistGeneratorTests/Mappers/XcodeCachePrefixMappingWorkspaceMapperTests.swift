import Foundation
import Mockable
import Path
import Testing
import struct TSCUtility.Version
import TuistConfig
import TuistConstants
import TuistCore
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

    private func makeSubject(enableCaching: Bool = true) -> XcodeCachePrefixMappingWorkspaceMapper {
        XcodeCachePrefixMappingWorkspaceMapper(
            tuist: Tuist(
                project: .generated(.test(generationOptions: .test(enableCaching: enableCaching))),
                fullHandle: nil,
                inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
                url: Constants.URLs.production
            )
        )
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

    @Test(.withMockedXcodeController)
    func map_whenXcode27_mapsScratchAndWorkspaceDirectoriesInEveryProject() async throws {
        // Given
        try stubXcodeVersion(Version(27, 0, 0))
        let subject = makeSubject()

        // When
        let (mapped, sideEffects) = try await subject.map(
            workspace: WorkspaceWithProjects(workspace: workspace, projects: [appProject, externalProject])
        )

        // Then
        #expect(sideEffects.isEmpty)
        let expected: SettingValue = .array([
            "$(inherited)",
            #""$(TUIST_PREFIX_MAPPING_WORKSPACE_DIR)/Tuist/.build=/^spm""#,
            #""$(TUIST_PREFIX_MAPPING_WORKSPACE_DIR)=/^workspace""#,
        ])
        for project in mapped.projects {
            #expect(project.settings.base["TUIST_PREFIX_MAPPING_WORKSPACE_DIR"] == .string("/Users/dev/app"))
            #expect(project.settings.base["SWIFT_OTHER_PREFIX_MAPPINGS"] == expected)
            #expect(project.settings.base["CLANG_OTHER_PREFIX_MAPPINGS"] == expected)
        }
    }

    /// Without packages there is no scratch directory to map, but first-party sources
    /// outside their own project directory still need the workspace mapping.
    @Test(.withMockedXcodeController)
    func map_whenNoExternalProjects_mapsOnlyTheWorkspaceDirectory() async throws {
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
                == .array(["$(inherited)", #""$(TUIST_PREFIX_MAPPING_WORKSPACE_DIR)=/^workspace""#])
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
                == .array(["/opt/shared=/^shared", #""$(TUIST_PREFIX_MAPPING_WORKSPACE_DIR)=/^workspace""#])
        )
    }

    /// Xcode splits a list element at spaces, so a workspace path with spaces stays in
    /// the plain workspace directory setting, out of the mapping elements.
    @Test(.withMockedXcodeController)
    func map_whenWorkspaceDirectoryHasSpaces_keepsItOutOfTheMappings() async throws {
        // Given
        try stubXcodeVersion(Version(27, 0, 0))
        let subject = makeSubject()
        let repository = try AbsolutePath(validating: "/Users/dev/my app")
        let workspace = Workspace.test(path: repository, xcWorkspacePath: repository.appending(component: "App.xcworkspace"))
        let project = externalProject(scratchDirectory: repository.appending(components: "Tuist", ".build"))

        // When
        let (mapped, _) = try await subject.map(
            workspace: WorkspaceWithProjects(workspace: workspace, projects: [project])
        )

        // Then
        let base = try #require(mapped.projects.first?.settings.base)
        #expect(base["TUIST_PREFIX_MAPPING_WORKSPACE_DIR"] == .string("/Users/dev/my app"))
        #expect(
            base["SWIFT_OTHER_PREFIX_MAPPINGS"] == .array([
                "$(inherited)",
                #""$(TUIST_PREFIX_MAPPING_WORKSPACE_DIR)/Tuist/.build=/^spm""#,
                #""$(TUIST_PREFIX_MAPPING_WORKSPACE_DIR)=/^workspace""#,
            ])
        )
    }

    /// A scratch directory outside the workspace is written as an absolute path, quoted
    /// and escaped so that spaces and quotes stay inside a single mapping.
    @Test(.withMockedXcodeController)
    func map_whenScratchDirectoryIsOutsideTheWorkspace_quotesItsAbsolutePath() async throws {
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
                #""$(TUIST_PREFIX_MAPPING_WORKSPACE_DIR)=/^workspace""#,
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
