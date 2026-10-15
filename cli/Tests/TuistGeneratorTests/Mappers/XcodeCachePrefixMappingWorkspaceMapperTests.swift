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

    private var xcconfigPath: AbsolutePath {
        XcodeCachePackagesXCConfig.path(xcWorkspacePath: workspace.xcWorkspacePath)
    }

    /// A project with a package that Xcode checks out into `SourcePackages`.
    private var appProjectWithXcodePackages: Project {
        var project = appProject
        project.packages = [.remote(url: "https://github.com/apple/swift-atomics", requirement: .exact("1.2.0"))]
        return project
    }

    private var packagesMappings: [String] {
        [
            #""$(TUIST_PREFIX_MAPPING_ROOT_DIR)/Tuist/.build=/^spm""#,
            #""$(TUIST_SOURCE_PACKAGES_DIR:standardizepath)=/^packages""#,
            #""$(OBJROOT)=/^intermediates""#,
            #""$(SYMROOT)=/^products""#,
            #""$(TUIST_PREFIX_MAPPING_ROOT_DIR)=/^root""#,
        ]
    }

    private var rootMappings: SettingValue {
        .array([
            "$(inherited)",
            #""$(TUIST_PREFIX_MAPPING_ROOT_DIR)/Tuist/.build=/^spm""#,
            #""$(OBJROOT)=/^intermediates""#,
            #""$(SYMROOT)=/^products""#,
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
        #expect(sideEffects == [.file(FileDescriptor(path: xcconfigPath, state: .absent))])
        for project in mapped.projects {
            #expect(project.settings.base["TUIST_PREFIX_MAPPING_ROOT_DIR"] == .string("/Users/dev/app"))
            #expect(project.settings.base["SWIFT_OTHER_PREFIX_MAPPINGS"] == rootMappings)
            #expect(project.settings.base["CLANG_OTHER_PREFIX_MAPPINGS"] == rootMappings)
        }
    }

    @Test(.withMockedXcodeController)
    func map_whenMultipleProjectsOptOut_usesAnUnambiguousSharedSourceNamespace() async throws {
        try stubXcodeVersion(Version(27, 0, 0))
        let tuist = Tuist(
            project: .generated(.test(generationOptions: .test(enableCaching: true))),
            fullHandle: nil,
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: Constants.URLs.production
        )
        let secondPath = repository.appending(component: "Library")
        let secondProject = Project.test(path: secondPath, sourceRootPath: secondPath, name: "Library")
        var projects: [Project] = []
        for var project in [appProject, secondProject] {
            project.settings = project.settings.with(base: [
                "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING": "NO",
                "CLANG_ENABLE_PROJECT_PREFIX_MAPPING": "NO",
            ])
            let (mapped, _) = try await XcodeCacheSettingsProjectMapper(tuist: tuist).map(project: project)
            projects.append(mapped)
        }

        let (mapped, _) = try await makeSubject().map(
            workspace: WorkspaceWithProjects(workspace: workspace, projects: projects)
        )

        for project in mapped.projects {
            for language in ["SWIFT", "CLANG"] {
                #expect(project.settings.base["\(language)_ENABLE_PROJECT_PREFIX_MAPPING"] == .string("NO"))
                #expect(project.settings.base["\(language)_OTHER_PREFIX_MAPPINGS"] == .array([
                    "$(inherited)",
                    #""$(OBJROOT)=/^intermediates""#,
                    #""$(SYMROOT)=/^products""#,
                    #""$(TUIST_PREFIX_MAPPING_ROOT_DIR)=/^root""#,
                ]))
            }
        }
    }

    @Test(.withMockedXcodeController)
    func map_whenProjectsAreOutsideTheRoot_preservesDefaultProjectMapping() async throws {
        try stubXcodeVersion(Version(27, 0, 0))
        let tuist = Tuist(
            project: .generated(.test(generationOptions: .test(enableCaching: true))),
            fullHandle: nil,
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: Constants.URLs.production
        )
        let siblingPath = repository.parentDirectory.appending(components: "shared", "Library")
        let sibling = Project.test(path: siblingPath, sourceRootPath: siblingPath, name: "Library")
        var projects: [Project] = []
        for project in [appProject, sibling] {
            let (mapped, _) = try await XcodeCacheSettingsProjectMapper(tuist: tuist).map(project: project)
            projects.append(mapped)
        }

        let (mapped, _) = try await makeSubject().map(
            workspace: WorkspaceWithProjects(workspace: workspace, projects: projects)
        )

        for project in mapped.projects {
            #expect(project.settings.base["SWIFT_ENABLE_PROJECT_PREFIX_MAPPING"] == .string("YES"))
            #expect(project.settings.base["CLANG_ENABLE_PROJECT_PREFIX_MAPPING"] == .string("YES"))
            #expect(project.settings.base["TUIST_PREFIX_MAPPING_ROOT_DIR"] == .string(repository.pathString))
        }
        #expect(mapped.projects.contains { $0.path == siblingPath })
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
    func map_whenNoExternalProjects_mapsBuildAndRootDirectories() async throws {
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
                == .array([
                    "$(inherited)",
                    #""$(OBJROOT)=/^intermediates""#,
                    #""$(SYMROOT)=/^products""#,
                    #""$(TUIST_PREFIX_MAPPING_ROOT_DIR)=/^root""#,
                ])
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
                == .array([
                    "/opt/shared=/^shared",
                    #""$(OBJROOT)=/^intermediates""#,
                    #""$(SYMROOT)=/^products""#,
                    #""$(TUIST_PREFIX_MAPPING_ROOT_DIR)=/^root""#,
                ])
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
                #""$(OBJROOT)=/^intermediates""#,
                #""$(SYMROOT)=/^products""#,
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

    /// Xcode checks the packages of `Project.packages` out into `SourcePackages`, outside
    /// every project directory and the root.
    @Test(.withMockedXcodeController)
    func map_whenProjectsHaveXcodePackages_mapsTheSourcePackagesDirectoryInEveryProject() async throws {
        // Given
        try stubXcodeVersion(Version(27, 0, 0))
        let subject = makeSubject()

        // When
        let (mapped, _) = try await subject.map(
            workspace: WorkspaceWithProjects(workspace: workspace, projects: [appProjectWithXcodePackages, externalProject])
        )

        // Then
        for project in mapped.projects {
            #expect(project.settings.base["TUIST_SOURCE_PACKAGES_DIR"] == .string("$(OBJROOT)/../../SourcePackages"))
            #expect(project.settings.base["SWIFT_OTHER_PREFIX_MAPPINGS"] == .array(["$(inherited)"] + packagesMappings))
            #expect(project.settings.base["CLANG_OTHER_PREFIX_MAPPINGS"] == .array(["$(inherited)"] + packagesMappings))
        }
    }

    /// The package targets don't read the projects' settings, so the same mappings go into
    /// an xcconfig that `xcodebuild` applies to every target.
    @Test(.withMockedXcodeController)
    func map_whenProjectsHaveXcodePackages_writesThePackagesXCConfig() async throws {
        // Given
        try stubXcodeVersion(Version(27, 0, 0))
        let subject = makeSubject()

        // When
        let (_, sideEffects) = try await subject.map(
            workspace: WorkspaceWithProjects(workspace: workspace, projects: [appProjectWithXcodePackages, externalProject])
        )

        // Then
        let mappings = (["$(inherited)"] + packagesMappings).joined(separator: " ")
        let expected = """
        // Generated by Tuist. Do not edit.
        //
        // Applies the Xcode cache prefix mappings to the targets of the packages in `Project.packages`,
        // which don't read the generated projects' build settings. `tuist xcodebuild`, `tuist build`
        // and `tuist test` pass it to xcodebuild through `XCODE_XCCONFIG_FILE`. Pass it to other
        // xcodebuild invocations with `-xcconfig`.

        TUIST_PREFIX_MAPPING_ROOT_DIR = /Users/dev/app
        TUIST_SOURCE_PACKAGES_DIR = $(OBJROOT)/../../SourcePackages
        TUIST_PREFIX_MAPPING_FOR_COVERAGE_ = YES
        TUIST_PREFIX_MAPPING_FOR_COVERAGE_NO = YES
        TUIST_PREFIX_MAPPING_FOR_COVERAGE_YES = NO
        SWIFT_ENABLE_PREFIX_MAPPING = $(inherited:default=$(TUIST_PREFIX_MAPPING_FOR_COVERAGE_$(CLANG_COVERAGE_MAPPING)))
        CLANG_ENABLE_PREFIX_MAPPING = $(inherited:default=$(TUIST_PREFIX_MAPPING_FOR_COVERAGE_$(CLANG_COVERAGE_MAPPING)))
        SWIFT_OTHER_PREFIX_MAPPINGS = \(mappings)
        CLANG_OTHER_PREFIX_MAPPINGS = \(mappings)

        """
        #expect(sideEffects == [.file(FileDescriptor(path: xcconfigPath, contents: Data(expected.utf8)))])
    }

    @Test(.withMockedXcodeController)
    func map_whenCachingDisabled_removesThePackagesXCConfig() async throws {
        // Given
        try stubXcodeVersion(Version(27, 0, 0))
        let subject = makeSubject(enableCaching: false)

        // When
        let (_, sideEffects) = try await subject.map(
            workspace: WorkspaceWithProjects(workspace: workspace, projects: [appProjectWithXcodePackages])
        )

        // Then
        #expect(sideEffects == [.file(FileDescriptor(path: xcconfigPath, state: .absent))])
    }
}
