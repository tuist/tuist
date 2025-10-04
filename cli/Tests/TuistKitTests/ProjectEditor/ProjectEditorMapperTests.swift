import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TSCUtility
import TuistCore
import TuistLoader
import TuistSupport
import XcodeGraph

@testable import TuistKit
@testable import TuistTesting

struct ProjectEditorMapperTests {
    private var subject: ProjectEditorMapper!
    private var swiftPackageManagerController: MockSwiftPackageManagerControlling!

    init() throws {
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock)
            .swiftVersion()
            .willReturn("5.2")

        Environment.mocked?.stubbedArchitecture = .arm64
        swiftPackageManagerController = MockSwiftPackageManagerControlling()
        subject = ProjectEditorMapper(
            swiftPackageManagerController: swiftPackageManagerController
        )
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func edit_when_there_are_helpers_and_setup_and_config_and_dependencies_and_tasks_and_plugins() async throws {
        // Given
        let sourceRootPath = try #require(FileSystem.temporaryTestDirectory)
        let projectManifestPaths = [sourceRootPath].map { $0.appending(component: "Project.swift") }
        let configPath = sourceRootPath.appending(components: Constants.tuistManifestFileName)
        let packageManifestPath = sourceRootPath.appending(components: Constants.tuistDirectoryName, "Package.swift")
        let helperPaths = [sourceRootPath].map { $0.appending(component: "Project+Template.swift") }
        let templates = [sourceRootPath].map { $0.appending(component: "template") }
        let templateResource = [sourceRootPath].map { $0.appending(component: "template.stencil") }
        let resourceSynthesizers = [sourceRootPath].map { $0.appending(component: "resourceSynthesizer") }
        let stencils = [sourceRootPath].map { $0.appending(component: "Stencil") }
        let projectDescriptionPath = sourceRootPath.appending(component: "ProjectDescription.framework")
        let tuistPath = try AbsolutePath(validating: "/usr/bin/foo/bar/tuist")
        let projectName = "Manifests"
        let projectsGroup = ProjectGroup.group(name: projectName)
        let pluginPaths = [
            sourceRootPath.appending(component: "PluginTwo"),
            sourceRootPath.appending(component: "PluginThree"),
        ].map { EditablePluginManifest(name: $0.basename, path: $0) }
        given(swiftPackageManagerController)
            .getToolsVersion(at: .any)
            .willReturn("5.5.0")

        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selected()
            .willReturn(.test(path: AbsolutePath("/Applications/Xcode.app")))

        // When
        let graph = try await subject.map(
            name: "TestManifests",
            tuistPath: tuistPath,
            sourceRootPath: sourceRootPath,
            destinationDirectory: sourceRootPath,
            configPath: configPath,
            packageManifestPath: packageManifestPath,
            projectManifests: projectManifestPaths,
            editablePluginManifests: pluginPaths,
            pluginProjectDescriptionHelpersModule: [],
            helpers: helperPaths,
            templateSources: templates,
            templateResources: templateResource,
            resourceSynthesizers: resourceSynthesizers,
            stencils: stencils,
            projectDescriptionSearchPath: projectDescriptionPath
        )

        let project = try #require(graph.projects.values.first(where: { $0.name == projectName }))
        let targets = graph.projects.values.flatMap(\.targets.values).sorted(by: { $0.name < $1.name })

        // Then
        #expect(graph.name == "TestManifests")

        #expect(targets.count == 9)

        // Generated Manifests target
        let manifestsTarget = try #require(
            project.targets.values.sorted()
                .first(where: { $0.name == sourceRootPath.basename + projectName })
        )
        #expect(targets.first(where: { $0.name.contains("Manifests") }) == manifestsTarget)

        print(targets.map(\.name))
        #expect(manifestsTarget.destinations == .macOS)
        #expect(manifestsTarget.product == .staticFramework)
        #expect(
            manifestsTarget.settings ==
                expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        #expect(manifestsTarget.sources.map(\.path) == projectManifestPaths)
        #expect(manifestsTarget.filesGroup == projectsGroup)
        #expect(Set(manifestsTarget.dependencies) == Set([
            .target(name: "ProjectDescriptionHelpers"),
            .target(name: "PluginTwo"),
            .target(name: "PluginThree"),
        ]))

        // Generated Helpers target
        let helpersTarget = try #require(project.targets.values.sorted().last(where: { $0.name == "ProjectDescriptionHelpers" }))
        #expect(targets.contains(helpersTarget) == true)

        #expect(helpersTarget.name == "ProjectDescriptionHelpers")
        #expect(helpersTarget.destinations == .macOS)
        #expect(helpersTarget.product == .staticFramework)
        #expect(
            helpersTarget.settings ==
                expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        #expect(helpersTarget.sources.map(\.path) == helperPaths)
        #expect(helpersTarget.filesGroup == projectsGroup)
        #expect(Set(manifestsTarget.dependencies) == Set([
            .target(name: "ProjectDescriptionHelpers"),
            .target(name: "PluginTwo"),
            .target(name: "PluginThree"),
        ]))

        // Generated Templates target
        let templatesTarget = try #require(project.targets.values.sorted().last(where: { $0.name == "Templates" }))
        #expect(targets.contains(templatesTarget) == true)

        #expect(templatesTarget.name == "Templates")
        #expect(templatesTarget.destinations == .macOS)
        #expect(templatesTarget.product == .staticFramework)
        #expect(
            templatesTarget.settings ==
                expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        #expect(templatesTarget.sources.map(\.path) == templates)
        #expect(templatesTarget.additionalFiles.map(\.path) == templateResource)
        #expect(templatesTarget.filesGroup == projectsGroup)
        #expect(Set(templatesTarget.dependencies) == Set([
            .target(name: "ProjectDescriptionHelpers"),
        ]))

        // Generated ResourceSynthesizers target
        let resourceSynthesizersTarget = try #require(
            project.targets.values.sorted()
                .last(where: { $0.name == "ResourceSynthesizers" })
        )
        #expect(targets.contains(resourceSynthesizersTarget) == true)

        #expect(resourceSynthesizersTarget.name == "ResourceSynthesizers")
        #expect(resourceSynthesizersTarget.destinations == .macOS)
        #expect(resourceSynthesizersTarget.product == .staticFramework)
        #expect(
            resourceSynthesizersTarget.settings ==
                expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        #expect(resourceSynthesizersTarget.additionalFiles.map(\.path) == resourceSynthesizers)
        #expect(resourceSynthesizersTarget.filesGroup == projectsGroup)
        #expect(Set(resourceSynthesizersTarget.dependencies) == Set([
            .target(name: "ProjectDescriptionHelpers"),
        ]))

        // Generated Stencils target
        let stencilsTarget = try #require(project.targets.values.sorted().last(where: { $0.name == "Stencils" }))
        #expect(targets.contains(stencilsTarget) == true)

        #expect(stencilsTarget.name == "Stencils")
        #expect(stencilsTarget.destinations == .macOS)
        #expect(stencilsTarget.product == .staticFramework)
        #expect(
            stencilsTarget.settings ==
                expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        #expect(stencilsTarget.sources.map(\.path) == stencils)
        #expect(stencilsTarget.filesGroup == projectsGroup)
        #expect(Set(stencilsTarget.dependencies) == Set([
            .target(name: "ProjectDescriptionHelpers"),
        ]))

        // Generated Config target
        let configTarget = try #require(project.targets.values.sorted().last(where: { $0.name == "Config" }))
        #expect(targets.contains(configTarget) == true)

        #expect(configTarget.name == "Config")
        #expect(configTarget.destinations == .macOS)
        #expect(configTarget.product == .staticFramework)
        #expect(
            configTarget.settings ==
                expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        #expect(configTarget.sources.map(\.path) == [configPath])
        #expect(configTarget.filesGroup == projectsGroup)
        #expect(configTarget.dependencies.isEmpty == true)

        // Generated Packages target
        let packagesTarget = try #require(project.targets.values.sorted().last(where: { $0.name == "Packages" }))
        #expect(targets.contains(packagesTarget) == true)

        #expect(packagesTarget.name == "Packages")
        #expect(packagesTarget.destinations == .macOS)
        #expect(packagesTarget.product == .staticFramework)
        var expectedPackagesSettings = expectedSettings(includePaths: [
            projectDescriptionPath,
            projectDescriptionPath.parentDirectory,
        ])
        expectedPackagesSettings = expectedPackagesSettings.with(
            base: expectedPackagesSettings.base.merging(
                [
                    "OTHER_SWIFT_FLAGS": .array([
                        "-package-description-version",
                        "5.5.0",
                        "-D", "TUIST",
                    ]),
                    "SWIFT_INCLUDE_PATHS": .array([
                        "$(DT_TOOLCHAIN_DIR)/usr/lib/swift/pm/ManifestAPI",
                    ]),
                    "SWIFT_VERSION": "5.0.0",
                ],
                uniquingKeysWith: {
                    switch ($0, $1) {
                    case let (.array(leftArray), .array(rightArray)):
                        return SettingValue.array(leftArray + rightArray)
                    default:
                        return $1
                    }
                }
            )
        )
        #expect(
            packagesTarget.settings ==
                expectedPackagesSettings
        )
        #expect(packagesTarget.dependencies == [.target(name: "ProjectDescriptionHelpers")])
        #expect(packagesTarget.sources.map(\.path) == [packageManifestPath])
        #expect(packagesTarget.filesGroup == projectsGroup)

        // Generated Project
        #expect(project.path == sourceRootPath.appending(component: projectName))
        #expect(project.name == projectName)
        #expect(project.settings == Settings(
            base: [:],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        ))
        #expect(project.filesGroup == projectsGroup)

        // Generated Scheme
        #expect(project.schemes.count == 1)
        let scheme = try #require(project.schemes.first)
        #expect(scheme.name == projectName)

        let buildAction = try #require(scheme.buildAction)
        #expect(buildAction.targets.lazy.map(\.name).sorted() == project.targets.values.map(\.name).sorted())

        let runAction = try #require(scheme.runAction)
        #expect(runAction.filePath == tuistPath)
        let generateArgument = "generate --path \(sourceRootPath)"
        #expect(runAction.arguments == Arguments(launchArguments: [LaunchArgument(name: generateArgument, isEnabled: true)]))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func edit_when_there_are_no_helpers_and_no_setup_and_no_config_and_no_dependencies() async throws {
        // Given
        let sourceRootPath = try #require(FileSystem.temporaryTestDirectory)
        let projectManifestPaths = [sourceRootPath].map { $0.appending(component: "Project.swift") }
        let helperPaths: [AbsolutePath] = []
        let templates: [AbsolutePath] = []
        let resourceSynthesizers: [AbsolutePath] = []
        let stencils: [AbsolutePath] = []
        let projectDescriptionPath = sourceRootPath.appending(component: "ProjectDescription.framework")
        let tuistPath = try AbsolutePath(validating: "/usr/bin/foo/bar/tuist")
        let projectName = "Manifests"
        let projectsGroup = ProjectGroup.group(name: projectName)

        // When
        let graph = try await subject.map(
            name: "TestManifests",
            tuistPath: tuistPath,
            sourceRootPath: sourceRootPath,
            destinationDirectory: sourceRootPath,
            configPath: nil,
            packageManifestPath: nil,
            projectManifests: projectManifestPaths,
            editablePluginManifests: [],
            pluginProjectDescriptionHelpersModule: [],
            helpers: helperPaths,
            templateSources: templates,
            templateResources: [],
            resourceSynthesizers: resourceSynthesizers,
            stencils: stencils,
            projectDescriptionSearchPath: projectDescriptionPath
        )

        let project = try #require(graph.projects.values.first)
        let targets = graph.projects.values.flatMap(\.targets.values).sorted(by: { $0.name < $1.name })

        // Then
        #expect(targets.count == 1)
        #expect(targets.flatMap(\.dependencies).isEmpty)

        // Generated Manifests target
        let manifestsTarget = try #require(
            project.targets.values.sorted()
                .last(where: { $0.name == sourceRootPath.basename + projectName })
        )

        #expect(manifestsTarget.destinations == .macOS)
        #expect(manifestsTarget.product == .staticFramework)
        #expect(
            manifestsTarget.settings ==
                expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        #expect(manifestsTarget.sources.map(\.path) == projectManifestPaths)
        #expect(manifestsTarget.filesGroup == projectsGroup)
        #expect(manifestsTarget.dependencies.isEmpty)

        // Generated Project
        #expect(project.path == sourceRootPath.appending(component: projectName))
        #expect(project.name == projectName)
        #expect(project.settings == Settings(
            base: [:],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        ))
        #expect(project.filesGroup == projectsGroup)

        // Generated Scheme
        #expect(project.schemes.count == 1)
        let scheme = try #require(project.schemes.first)
        #expect(scheme.name == projectName)

        let buildAction = try #require(scheme.buildAction)
        #expect(buildAction.targets.map(\.name) == targets.map(\.name))

        let runAction = try #require(scheme.runAction)
        #expect(runAction.filePath == tuistPath)
        let generateArgument = "generate --path \(sourceRootPath)"
        #expect(runAction.arguments == Arguments(launchArguments: [LaunchArgument(name: generateArgument, isEnabled: true)]))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func tuist_edit_with_more_than_one_manifest() async throws {
        // Given
        let sourceRootPath = try #require(FileSystem.temporaryTestDirectory)
        let configPath = sourceRootPath.appending(components: Constants.tuistManifestFileName)
        let otherProjectPath = "Module"
        let projectManifestPaths = [
            sourceRootPath.appending(component: "Project.swift"),
            sourceRootPath.appending(component: otherProjectPath).appending(component: "Project.swift"),
        ]
        let helperPaths: [AbsolutePath] = []
        let templates: [AbsolutePath] = []
        let resourceSynthesizers: [AbsolutePath] = []
        let stencils: [AbsolutePath] = []
        let projectDescriptionPath = sourceRootPath.appending(component: "ProjectDescription.framework")
        let tuistPath = try AbsolutePath(validating: "/usr/bin/foo/bar/tuist")
        let projectName = "Manifests"

        // When
        let graph = try await subject.map(
            name: "TestManifests",
            tuistPath: tuistPath,
            sourceRootPath: sourceRootPath,
            destinationDirectory: sourceRootPath,
            configPath: configPath,
            packageManifestPath: nil,
            projectManifests: projectManifestPaths,
            editablePluginManifests: [],
            pluginProjectDescriptionHelpersModule: [],
            helpers: helperPaths,
            templateSources: templates,
            templateResources: [],
            resourceSynthesizers: resourceSynthesizers,
            stencils: stencils,
            projectDescriptionSearchPath: projectDescriptionPath
        )

        let project = try #require(graph.projects.values.first)
        let targets = graph.projects.values.flatMap(\.targets.values).sorted(by: { $0.name < $1.name })

        // Then

        #expect(targets.count == 3)
        #expect(targets.flatMap(\.dependencies).isEmpty == true)

        // Generated Manifests target
        let manifestOneTarget = try #require(project.targets.values.sorted().last(where: { $0.name == "ModuleManifests" }))

        #expect(manifestOneTarget.name == "ModuleManifests")
        #expect(manifestOneTarget.destinations == .macOS)
        #expect(manifestOneTarget.product == .staticFramework)
        #expect(
            manifestOneTarget.settings ==
                expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        #expect(manifestOneTarget.sources.map(\.path) == [try #require(projectManifestPaths.last)])
        #expect(manifestOneTarget.filesGroup == .group(name: projectName))
        #expect(manifestOneTarget.dependencies.isEmpty == true)

        // Generated Manifests target
        let manifestTwoTarget = try #require(
            project.targets.values.sorted()
                .last(where: { $0.name == "\(sourceRootPath.basename)Manifests" })
        )

        #expect(manifestTwoTarget.destinations == .macOS)
        #expect(manifestTwoTarget.product == .staticFramework)
        #expect(
            manifestTwoTarget.settings ==
                expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        #expect(manifestTwoTarget.sources.map(\.path) == [try #require(projectManifestPaths.first)])
        #expect(manifestTwoTarget.filesGroup == .group(name: projectName))
        #expect(manifestTwoTarget.dependencies.isEmpty == true)

        // Generated Config target
        let configTarget = try #require(project.targets.values.sorted().last(where: { $0.name == "Config" }))

        #expect(configTarget.name == "Config")
        #expect(configTarget.destinations == .macOS)
        #expect(configTarget.product == .staticFramework)
        #expect(
            configTarget.settings ==
                expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        #expect(configTarget.sources.map(\.path) == [configPath])
        #expect(configTarget.filesGroup == .group(name: projectName))
        #expect(configTarget.dependencies.isEmpty == true)

        // Generated Project
        #expect(project.path == sourceRootPath.appending(component: projectName))
        #expect(project.name == projectName)
        #expect(project.settings == Settings(
            base: [:],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        ))
        #expect(project.filesGroup == .group(name: projectName))

        // Generated Scheme
        #expect(project.schemes.count == 1)
        let scheme = try #require(project.schemes.first)
        #expect(scheme.name == projectName)

        let buildAction = try #require(scheme.buildAction)
        #expect(buildAction.targets.map(\.name).sorted() == targets.map(\.name).sorted())

        let runAction = try #require(scheme.runAction)
        #expect(runAction.filePath == tuistPath)
        let generateArgument = "generate --path \(sourceRootPath)"
        #expect(runAction.arguments == Arguments(launchArguments: [LaunchArgument(name: generateArgument, isEnabled: true)]))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func tuist_edit_with_one_plugin_no_projects() async throws {
        let sourceRootPath = try #require(FileSystem.temporaryTestDirectory)
        let pluginManifestPaths = [sourceRootPath].map { $0.appending(component: "Plugin.swift") }
        let editablePluginManifests = pluginManifestPaths.map {
            EditablePluginManifest(name: $0.parentDirectory.basename, path: $0.parentDirectory)
        }
        let helperPaths: [AbsolutePath] = []
        let templates: [AbsolutePath] = []
        let resourceSynthesizers: [AbsolutePath] = []
        let stencils: [AbsolutePath] = []
        let projectDescriptionPath = sourceRootPath.appending(component: "ProjectDescription.framework")
        let tuistPath = try AbsolutePath(validating: "/usr/bin/foo/bar/tuist")
        let projectName = "Plugins"
        let projectsGroup = ProjectGroup.group(name: projectName)

        // When
        let graph = try await subject.map(
            name: "TestManifests",
            tuistPath: tuistPath,
            sourceRootPath: sourceRootPath,
            destinationDirectory: sourceRootPath,
            configPath: nil,
            packageManifestPath: nil,
            projectManifests: [],
            editablePluginManifests: editablePluginManifests,
            pluginProjectDescriptionHelpersModule: [],
            helpers: helperPaths,
            templateSources: templates,
            templateResources: [],
            resourceSynthesizers: resourceSynthesizers,
            stencils: stencils,
            projectDescriptionSearchPath: projectDescriptionPath
        )

        let project = try #require(graph.projects.values.first)
        let targets = graph.projects.values.flatMap(\.targets.values).sorted(by: { $0.name < $1.name })

        // Then
        #expect(targets.count == 1)
        #expect(targets.flatMap(\.dependencies).isEmpty)

        // Generated Plugin target
        let pluginTarget = try #require(project.targets.values.sorted().last(where: { $0.name == sourceRootPath.basename }))

        #expect(pluginTarget.destinations == .macOS)
        #expect(pluginTarget.product == .staticFramework)
        #expect(
            pluginTarget.settings ==
                expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        #expect(pluginTarget.sources.map(\.path) == pluginManifestPaths)
        #expect(pluginTarget.filesGroup == projectsGroup)
        #expect(pluginTarget.dependencies.isEmpty)

        // Generated Project
        #expect(project.path == sourceRootPath.appending(component: projectName))
        #expect(project.name == projectName)
        #expect(project.settings == Settings(
            base: [:],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        ))
        #expect(project.filesGroup == projectsGroup)

        // Generated Schemes
        #expect(project.schemes.count == 2)
        let schemes = project.schemes
        #expect(schemes.map(\.name).sorted() == [pluginTarget.name, "Plugins"].sorted())

        let pluginBuildAction = try #require(schemes.first?.buildAction)
        #expect(pluginBuildAction.targets.map(\.name) == [pluginTarget.name])

        let allPluginsBuildAction = try #require(schemes.last?.buildAction)
        #expect(allPluginsBuildAction.targets.map(\.name).sorted() == targets.map(\.name).sorted())
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func tuist_edit_with_more_than_one_plugin_no_projects() async throws {
        let sourceRootPath = try #require(FileSystem.temporaryTestDirectory)
        let pluginManifestPaths = [
            sourceRootPath.appending(component: "A").appending(component: "Plugin.swift"),
            sourceRootPath.appending(component: "B").appending(component: "Plugin.swift"),
        ]
        let editablePluginManifests = pluginManifestPaths.map {
            EditablePluginManifest(name: $0.parentDirectory.basename, path: $0.parentDirectory)
        }
        let helperPaths: [AbsolutePath] = []
        let templates: [AbsolutePath] = []
        let resourceSynthesizers: [AbsolutePath] = []
        let stencils: [AbsolutePath] = []
        let projectDescriptionPath = sourceRootPath.appending(component: "ProjectDescription.framework")
        let tuistPath = try AbsolutePath(validating: "/usr/bin/foo/bar/tuist")
        let projectName = "Plugins"
        let projectsGroup = ProjectGroup.group(name: projectName)

        // When
        let graph = try await subject.map(
            name: "TestManifests",
            tuistPath: tuistPath,
            sourceRootPath: sourceRootPath,
            destinationDirectory: sourceRootPath,
            configPath: nil,
            packageManifestPath: nil,
            projectManifests: [],
            editablePluginManifests: editablePluginManifests,
            pluginProjectDescriptionHelpersModule: [],
            helpers: helperPaths,
            templateSources: templates,
            templateResources: [],
            resourceSynthesizers: resourceSynthesizers,
            stencils: stencils,
            projectDescriptionSearchPath: projectDescriptionPath
        )

        let project = try #require(graph.projects.values.first)
        let targets = graph.projects.values.flatMap(\.targets.values).sorted(by: { $0.name < $1.name })

        // Then
        #expect(targets.count == 2)
        #expect(targets.flatMap(\.dependencies).isEmpty)

        // Generated first plugin target
        let firstPluginTarget = try #require(project.targets.values.sorted().last(where: { $0.name == "A" }))

        #expect(firstPluginTarget.destinations == .macOS)
        #expect(firstPluginTarget.product == .staticFramework)
        #expect(
            firstPluginTarget.settings ==
                expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        #expect(firstPluginTarget.sources.map(\.path) == [pluginManifestPaths[0]])
        #expect(firstPluginTarget.filesGroup == projectsGroup)
        #expect(firstPluginTarget.dependencies.isEmpty)

        // Generated second plugin target
        let secondPluginTarget = try #require(project.targets.values.sorted().last(where: { $0.name == "B" }))

        #expect(secondPluginTarget.destinations == .macOS)
        #expect(secondPluginTarget.product == .staticFramework)
        #expect(
            secondPluginTarget.settings ==
                expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        #expect(secondPluginTarget.sources.map(\.path) == [pluginManifestPaths[1]])
        #expect(secondPluginTarget.filesGroup == projectsGroup)
        #expect(secondPluginTarget.dependencies.isEmpty == true)

        // Generated Project
        #expect(project.path == sourceRootPath.appending(component: projectName))
        #expect(project.name == projectName)
        #expect(project.settings == Settings(
            base: [:],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        ))
        #expect(project.filesGroup == projectsGroup)

        // Generated Schemes
        let schemes = project.schemes.sorted(by: { $0.name < $1.name })
        #expect(project.schemes.count == 3)
        #expect(
            schemes.map(\.name) ==
                [firstPluginTarget.name, secondPluginTarget.name, "Plugins"].sorted()
        )

        let firstBuildAction = try #require(schemes[0].buildAction)
        #expect(
            firstBuildAction.targets.map(\.name) ==
                [firstPluginTarget].map(\.name)
        )

        let secondBuildAction = try #require(schemes[1].buildAction)
        #expect(secondBuildAction.targets.map(\.name) == [secondPluginTarget].map(\.name))

        let pluginsBuildAction = try #require(schemes[2].buildAction)
        #expect(
            pluginsBuildAction.targets.map(\.name).sorted() ==
                [firstPluginTarget, secondPluginTarget].map(\.name).sorted()
        )
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func tuist_edit_plugin_only_takes_required_sources() async throws {
        // Given
        let sourceRootPath = try #require(FileSystem.temporaryTestDirectory)
        let pluginManifestPath = sourceRootPath.appending(component: "Plugin.swift")
        let editablePluginManifests = [
            EditablePluginManifest(name: pluginManifestPath.parentDirectory.basename, path: pluginManifestPath.parentDirectory),
        ]
        let helperPaths: [AbsolutePath] = []
        let templates: [AbsolutePath] = []
        let resourceSynthesizers: [AbsolutePath] = []
        let stencils: [AbsolutePath] = []
        let projectDescriptionPath = sourceRootPath.appending(component: "ProjectDescription.framework")
        let tuistPath = try AbsolutePath(validating: "/usr/bin/foo/bar/tuist")
        try await TuistTest.createFiles([
            "Unrelated/Source.swift",
            "Source.swift",
            "ProjectDescriptionHelpers/data.json",
            "Templates/strings.stencil",
        ])
        let helperSources = try await TuistTest.createFiles([
            "ProjectDescriptionHelpers/HelperA.swift",
            "ProjectDescriptionHelpers/HelperB.swift",
        ])
        let templateSources = try await TuistTest.createFiles([
            "Templates/custom.swift",
            "Templates/strings.stencil",
        ])
        // When
        let graph = try await subject.map(
            name: "TestManifests",
            tuistPath: tuistPath,
            sourceRootPath: sourceRootPath,
            destinationDirectory: sourceRootPath,
            configPath: nil,
            packageManifestPath: nil,
            projectManifests: [],
            editablePluginManifests: editablePluginManifests,
            pluginProjectDescriptionHelpersModule: [],
            helpers: helperPaths,
            templateSources: templates,
            templateResources: [],
            resourceSynthesizers: resourceSynthesizers,
            stencils: stencils,
            projectDescriptionSearchPath: projectDescriptionPath
        )

        // Then
        let project = try #require(graph.projects.values.first)
        let pluginTarget = try #require(project.targets.values.first)

        #expect(
            pluginTarget.sources.sorted(by: { $0.path < $1.path }) ==
                ([pluginManifestPath] + helperSources + templateSources).map { SourceFile(path: $0) }
        )
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func tuist_edit_project_with_plugin() async throws {
        // Given
        let sourceRootPath = try #require(FileSystem.temporaryTestDirectory)
        let projectManifestPaths = [sourceRootPath].map { $0.appending(component: "Project.swift") }
        let helperPaths: [AbsolutePath] = [sourceRootPath].map { $0.appending(components: "Tuist", "ProjectDescriptionHelpers") }
        let templates: [AbsolutePath] = []
        let resourceSynthesizers: [AbsolutePath] = []
        let stencils: [AbsolutePath] = []
        let projectDescriptionPath = sourceRootPath.appending(components: "Frameworks", "ProjectDescription.framework")
        let tuistPath = try AbsolutePath(validating: "/usr/bin/foo/bar/tuist")
        let manifestsProjectName = "Manifests"
        let pluginsProjectName = "Plugins"
        let projectsGroup = ProjectGroup.group(name: manifestsProjectName)
        let pluginsGroup = ProjectGroup.group(name: pluginsProjectName)
        let localPlugin = EditablePluginManifest(name: "ALocalPlugin", path: sourceRootPath.appending(component: "ALocalPlugin"))
        let remotePlugin = ProjectDescriptionHelpersModule(name: "RemotePlugin", path: "/path/to/remote/plugin")

        // When
        let graph = try await subject.map(
            name: "TestManifests",
            tuistPath: tuistPath,
            sourceRootPath: sourceRootPath,
            destinationDirectory: sourceRootPath,
            configPath: nil,
            packageManifestPath: nil,
            projectManifests: projectManifestPaths,
            editablePluginManifests: [localPlugin],
            pluginProjectDescriptionHelpersModule: [remotePlugin],
            helpers: helperPaths,
            templateSources: templates,
            templateResources: [],
            resourceSynthesizers: resourceSynthesizers,
            stencils: stencils,
            projectDescriptionSearchPath: projectDescriptionPath
        )

        let pluginsProject = try #require(graph.projects.values.first(where: { $0.name == pluginsProjectName }))
        let manifestsProject = try #require(graph.projects.values.first(where: { $0.name == manifestsProjectName }))
        let targets = graph.projects.values.flatMap(\.targets.values).sorted(by: { $0.name < $1.name })
        let localPluginTarget = try #require(targets.first(where: { $0.name == "ALocalPlugin" }))
        let helpersTarget = try #require(targets.first(where: { $0.name == "ProjectDescriptionHelpers" }))
        let manifestsTarget = try #require(targets.first(where: { $0 != localPluginTarget && $0 != helpersTarget }))

        // Then
        #expect(targets.count == 3)

        // Local plugin target
        #expect(localPluginTarget.destinations == .macOS)
        #expect(localPluginTarget.product == .staticFramework)
        #expect(localPluginTarget.sources.map(\.path).first?.parentDirectory == localPlugin.path)
        #expect(localPluginTarget.filesGroup == pluginsGroup)
        #expect(localPluginTarget.dependencies.isEmpty)
        #expect(
            localPluginTarget.settings ==
                expectedSettings(includePaths: [
                    projectDescriptionPath,
                    projectDescriptionPath.parentDirectory,
                ])
        )

        // ProjectDescriptionHelpers target
        #expect(helpersTarget.destinations == .macOS)
        #expect(helpersTarget.product == .staticFramework)
        #expect(helpersTarget.sources.map(\.path).first == helperPaths.first)
        #expect(helpersTarget.filesGroup == projectsGroup)
        // Helpers can depend on local editable plugins
        #expect(helpersTarget.dependencies == [
            .target(name: localPluginTarget.name),
        ])
        #expect(
            helpersTarget.settings ==
                expectedSettings(includePaths: [
                    projectDescriptionPath,
                    projectDescriptionPath.parentDirectory,
                    // Helpers can include pre-built remote plugins
                    remotePlugin.path.parentDirectory,
                ])
        )

        // Generated Manifests target
        #expect(manifestsTarget.destinations == .macOS)
        #expect(manifestsTarget.product == .staticFramework)
        #expect(manifestsTarget.sources.map(\.path) == projectManifestPaths)
        #expect(manifestsTarget.filesGroup == projectsGroup)
        #expect(
            manifestsTarget.dependencies ==
                [
                    .target(name: "ProjectDescriptionHelpers"),
                    .target(name: "ALocalPlugin"),
                ]
        )
        #expect(
            manifestsTarget.settings ==
                expectedSettings(includePaths: [
                    projectDescriptionPath,
                    projectDescriptionPath.parentDirectory,
                    // Manifests can include plugins
                    remotePlugin.path.parentDirectory,
                ])
        )

        // Generated manifests Project
        let manifestsScheme = try #require(manifestsProject.schemes.first)
        let manifestsBuildAction = try #require(manifestsScheme.buildAction)
        let manifestsRunAction = try #require(manifestsScheme.runAction)
        #expect(manifestsProject.path == sourceRootPath.appending(component: manifestsProjectName))
        #expect(manifestsProject.name == manifestsProjectName)
        #expect(manifestsProject.settings == Settings(
            base: [:],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        ))
        #expect(manifestsProject.filesGroup == projectsGroup)
        #expect(manifestsProject.schemes.count == 1)
        #expect(manifestsScheme.name == manifestsProjectName)
        #expect(
            manifestsBuildAction.targets.map(\.name).sorted() ==
                [manifestsTarget.name, "ProjectDescriptionHelpers"].sorted()
        )
        #expect(manifestsRunAction.filePath == tuistPath)
        #expect(
            manifestsRunAction.arguments ==
                Arguments(launchArguments: [LaunchArgument(name: "generate --path \(sourceRootPath)", isEnabled: true)])
        )

        // Generated plugins project for local plugins
        let schemes = pluginsProject.schemes
        let aLocalPluginScheme = try #require(schemes.first(where: { $0.name == "ALocalPlugin" }))
        let pluginsScheme = try #require(schemes.first(where: { $0.name == pluginsProjectName }))
        #expect(pluginsProject.path == sourceRootPath.appending(component: pluginsProjectName))
        #expect(pluginsProject.name == pluginsProjectName)
        #expect(pluginsProject.settings == Settings(
            base: [:],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        ))
        #expect(pluginsProject.filesGroup == pluginsGroup)
        #expect(pluginsProject.schemes.count == 2)
        #expect(aLocalPluginScheme.buildAction?.targets.map(\.name).sorted() == [localPlugin.name])
        #expect(pluginsScheme.buildAction?.targets.map(\.name).sorted() == [localPlugin.name])
    }

    private func expectedSettings(includePaths: [AbsolutePath]) -> Settings {
        let paths = includePaths
            .map(\.pathString)
            .map { "\"\($0)\"" }
        return Settings(
            base: [
                "FRAMEWORK_SEARCH_PATHS": .array(paths),
                "LIBRARY_SEARCH_PATHS": .array(paths),
                "SWIFT_INCLUDE_PATHS": .array(paths),
                "SWIFT_VERSION": .string("5.2"),
            ],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        )
    }
}
