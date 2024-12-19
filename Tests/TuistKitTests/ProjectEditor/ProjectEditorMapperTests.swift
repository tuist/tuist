import Foundation
import Mockable
import Path
import TSCUtility
import TuistCore
import TuistLoader
import TuistSupport
import XcodeGraph
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class ProjectEditorMapperTests: TuistUnitTestCase {
    private var subject: ProjectEditorMapper!
    private var swiftPackageManagerController: MockSwiftPackageManagerControlling!

    override func setUp() {
        super.setUp()

        given(swiftVersionProvider)
            .swiftVersion()
            .willReturn("5.2")

        developerEnvironment.stubbedArchitecture = .arm64
        swiftPackageManagerController = MockSwiftPackageManagerControlling()
        subject = ProjectEditorMapper(
            swiftPackageManagerController: swiftPackageManagerController
        )
    }

    override func tearDown() {
        swiftPackageManagerController = nil
        subject = nil
        super.tearDown()
    }

    func test_edit_when_there_are_helpers_and_setup_and_config_and_dependencies_and_tasks_and_plugins() async throws {
        // Given
        let sourceRootPath = try temporaryPath()
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
        given(xcodeController)
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

        let project = try XCTUnwrap(graph.projects.values.first(where: { $0.name == projectName }))
        let targets = graph.projects.values.flatMap(\.targets.values).sorted(by: { $0.name < $1.name })

        // Then
        XCTAssertEqual(graph.name, "TestManifests")

        XCTAssertEqual(targets.count, 9)

        // Generated Manifests target
        let manifestsTarget = try XCTUnwrap(
            project.targets.values.sorted()
                .first(where: { $0.name == sourceRootPath.basename + projectName })
        )
        XCTAssertEqual(targets.last, manifestsTarget)

        XCTAssertEqual(manifestsTarget.destinations, .macOS)
        XCTAssertEqual(manifestsTarget.product, .staticFramework)
        XCTAssertEqual(
            manifestsTarget.settings,
            expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        XCTAssertEqual(manifestsTarget.sources.map(\.path), projectManifestPaths)
        XCTAssertEqual(manifestsTarget.filesGroup, projectsGroup)
        XCTAssertEqual(Set(manifestsTarget.dependencies), Set([
            .target(name: "ProjectDescriptionHelpers"),
            .target(name: "PluginTwo"),
            .target(name: "PluginThree"),
        ]))

        // Generated Helpers target
        let helpersTarget = try XCTUnwrap(project.targets.values.sorted().last(where: { $0.name == "ProjectDescriptionHelpers" }))
        XCTAssertTrue(targets.contains(helpersTarget))

        XCTAssertEqual(helpersTarget.name, "ProjectDescriptionHelpers")
        XCTAssertEqual(helpersTarget.destinations, .macOS)
        XCTAssertEqual(helpersTarget.product, .staticFramework)
        XCTAssertEqual(
            helpersTarget.settings,
            expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        XCTAssertEqual(helpersTarget.sources.map(\.path), helperPaths)
        XCTAssertEqual(helpersTarget.filesGroup, projectsGroup)
        XCTAssertEqual(Set(manifestsTarget.dependencies), Set([
            .target(name: "ProjectDescriptionHelpers"),
            .target(name: "PluginTwo"),
            .target(name: "PluginThree"),
        ]))

        // Generated Templates target
        let templatesTarget = try XCTUnwrap(project.targets.values.sorted().last(where: { $0.name == "Templates" }))
        XCTAssertTrue(targets.contains(templatesTarget))

        XCTAssertEqual(templatesTarget.name, "Templates")
        XCTAssertEqual(templatesTarget.destinations, .macOS)
        XCTAssertEqual(templatesTarget.product, .staticFramework)
        XCTAssertEqual(
            templatesTarget.settings,
            expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        XCTAssertEqual(templatesTarget.sources.map(\.path), templates)
        XCTAssertEqual(templatesTarget.additionalFiles.map(\.path), templateResource)
        XCTAssertEqual(templatesTarget.filesGroup, projectsGroup)
        XCTAssertEqual(Set(templatesTarget.dependencies), Set([
            .target(name: "ProjectDescriptionHelpers"),
        ]))

        // Generated ResourceSynthesizers target
        let resourceSynthesizersTarget = try XCTUnwrap(
            project.targets.values.sorted()
                .last(where: { $0.name == "ResourceSynthesizers" })
        )
        XCTAssertTrue(targets.contains(resourceSynthesizersTarget))

        XCTAssertEqual(resourceSynthesizersTarget.name, "ResourceSynthesizers")
        XCTAssertEqual(resourceSynthesizersTarget.destinations, .macOS)
        XCTAssertEqual(resourceSynthesizersTarget.product, .staticFramework)
        XCTAssertEqual(
            resourceSynthesizersTarget.settings,
            expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        XCTAssertEqual(resourceSynthesizersTarget.additionalFiles.map(\.path), resourceSynthesizers)
        XCTAssertEqual(resourceSynthesizersTarget.filesGroup, projectsGroup)
        XCTAssertEqual(Set(resourceSynthesizersTarget.dependencies), Set([
            .target(name: "ProjectDescriptionHelpers"),
        ]))

        // Generated Stencils target
        let stencilsTarget = try XCTUnwrap(project.targets.values.sorted().last(where: { $0.name == "Stencils" }))
        XCTAssertTrue(targets.contains(stencilsTarget))

        XCTAssertEqual(stencilsTarget.name, "Stencils")
        XCTAssertEqual(stencilsTarget.destinations, .macOS)
        XCTAssertEqual(stencilsTarget.product, .staticFramework)
        XCTAssertEqual(
            stencilsTarget.settings,
            expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        XCTAssertEqual(stencilsTarget.sources.map(\.path), stencils)
        XCTAssertEqual(stencilsTarget.filesGroup, projectsGroup)
        XCTAssertEqual(Set(stencilsTarget.dependencies), Set([
            .target(name: "ProjectDescriptionHelpers"),
        ]))

        // Generated Config target
        let configTarget = try XCTUnwrap(project.targets.values.sorted().last(where: { $0.name == "Config" }))
        XCTAssertTrue(targets.contains(configTarget))

        XCTAssertEqual(configTarget.name, "Config")
        XCTAssertEqual(configTarget.destinations, .macOS)
        XCTAssertEqual(configTarget.product, .staticFramework)
        XCTAssertEqual(
            configTarget.settings,
            expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        XCTAssertEqual(configTarget.sources.map(\.path), [configPath])
        XCTAssertEqual(configTarget.filesGroup, projectsGroup)
        XCTAssertEmpty(configTarget.dependencies)

        // Generated Packages target
        let packagesTarget = try XCTUnwrap(project.targets.values.sorted().last(where: { $0.name == "Packages" }))
        XCTAssertTrue(targets.contains(packagesTarget))

        XCTAssertEqual(packagesTarget.name, "Packages")
        XCTAssertEqual(packagesTarget.destinations, .macOS)
        XCTAssertEqual(packagesTarget.product, .staticFramework)
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
                        "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/pm/ManifestAPI",
                    ]),
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
        XCTAssertEqual(
            packagesTarget.settings,
            expectedPackagesSettings
        )
        XCTAssertEqual(packagesTarget.dependencies, [.target(name: "ProjectDescriptionHelpers")])
        XCTAssertEqual(packagesTarget.sources.map(\.path), [packageManifestPath])
        XCTAssertEqual(packagesTarget.filesGroup, projectsGroup)

        // Generated Project
        XCTAssertEqual(project.path, sourceRootPath.appending(component: projectName))
        XCTAssertEqual(project.name, projectName)
        XCTAssertEqual(project.settings, Settings(
            base: [:],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        ))
        XCTAssertEqual(project.filesGroup, projectsGroup)

        // Generated Scheme
        XCTAssertEqual(project.schemes.count, 1)
        let scheme = try XCTUnwrap(project.schemes.first)
        XCTAssertEqual(scheme.name, projectName)

        let buildAction = try XCTUnwrap(scheme.buildAction)
        XCTAssertEqual(buildAction.targets.lazy.map(\.name).sorted(), project.targets.values.map(\.name).sorted())

        let runAction = try XCTUnwrap(scheme.runAction)
        XCTAssertEqual(runAction.filePath, tuistPath)
        let generateArgument = "generate --path \(sourceRootPath)"
        XCTAssertEqual(runAction.arguments, Arguments(launchArguments: [LaunchArgument(name: generateArgument, isEnabled: true)]))
    }

    func test_edit_when_there_are_no_helpers_and_no_setup_and_no_config_and_no_dependencies() async throws {
        // Given
        let sourceRootPath = try temporaryPath()
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

        let project = try XCTUnwrap(graph.projects.values.first)
        let targets = graph.projects.values.flatMap(\.targets.values).sorted(by: { $0.name < $1.name })

        // Then
        XCTAssertEqual(targets.count, 1)
        XCTAssertEmpty(targets.flatMap(\.dependencies))

        // Generated Manifests target
        let manifestsTarget = try XCTUnwrap(
            project.targets.values.sorted()
                .last(where: { $0.name == sourceRootPath.basename + projectName })
        )

        XCTAssertEqual(manifestsTarget.destinations, .macOS)
        XCTAssertEqual(manifestsTarget.product, .staticFramework)
        XCTAssertEqual(
            manifestsTarget.settings,
            expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        XCTAssertEqual(manifestsTarget.sources.map(\.path), projectManifestPaths)
        XCTAssertEqual(manifestsTarget.filesGroup, projectsGroup)
        XCTAssertEmpty(manifestsTarget.dependencies)

        // Generated Project
        XCTAssertEqual(project.path, sourceRootPath.appending(component: projectName))
        XCTAssertEqual(project.name, projectName)
        XCTAssertEqual(project.settings, Settings(
            base: [:],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        ))
        XCTAssertEqual(project.filesGroup, projectsGroup)

        // Generated Scheme
        XCTAssertEqual(project.schemes.count, 1)
        let scheme = try XCTUnwrap(project.schemes.first)
        XCTAssertEqual(scheme.name, projectName)

        let buildAction = try XCTUnwrap(scheme.buildAction)
        XCTAssertEqual(buildAction.targets.map(\.name), targets.map(\.name))

        let runAction = try XCTUnwrap(scheme.runAction)
        XCTAssertEqual(runAction.filePath, tuistPath)
        let generateArgument = "generate --path \(sourceRootPath)"
        XCTAssertEqual(runAction.arguments, Arguments(launchArguments: [LaunchArgument(name: generateArgument, isEnabled: true)]))
    }

    func test_tuist_edit_with_more_than_one_manifest() async throws {
        // Given
        let sourceRootPath = try temporaryPath()
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

        let project = try XCTUnwrap(graph.projects.values.first)
        let targets = graph.projects.values.flatMap(\.targets.values).sorted(by: { $0.name < $1.name })

        // Then

        XCTAssertEqual(targets.count, 3)
        XCTAssertEmpty(targets.flatMap(\.dependencies))

        // Generated Manifests target
        let manifestOneTarget = try XCTUnwrap(project.targets.values.sorted().last(where: { $0.name == "ModuleManifests" }))

        XCTAssertEqual(manifestOneTarget.name, "ModuleManifests")
        XCTAssertEqual(manifestOneTarget.destinations, .macOS)
        XCTAssertEqual(manifestOneTarget.product, .staticFramework)
        XCTAssertEqual(
            manifestOneTarget.settings,
            expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        XCTAssertEqual(manifestOneTarget.sources.map(\.path), [try XCTUnwrap(projectManifestPaths.last)])
        XCTAssertEqual(manifestOneTarget.filesGroup, .group(name: projectName))
        XCTAssertEmpty(manifestOneTarget.dependencies)

        // Generated Manifests target
        let manifestTwoTarget = try XCTUnwrap(
            project.targets.values.sorted()
                .last(where: { $0.name == "\(sourceRootPath.basename)Manifests" })
        )

        XCTAssertEqual(manifestTwoTarget.destinations, .macOS)
        XCTAssertEqual(manifestTwoTarget.product, .staticFramework)
        XCTAssertEqual(
            manifestTwoTarget.settings,
            expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        XCTAssertEqual(manifestTwoTarget.sources.map(\.path), [try XCTUnwrap(projectManifestPaths.first)])
        XCTAssertEqual(manifestTwoTarget.filesGroup, .group(name: projectName))
        XCTAssertEmpty(manifestTwoTarget.dependencies)

        // Generated Config target
        let configTarget = try XCTUnwrap(project.targets.values.sorted().last(where: { $0.name == "Config" }))

        XCTAssertEqual(configTarget.name, "Config")
        XCTAssertEqual(configTarget.destinations, .macOS)
        XCTAssertEqual(configTarget.product, .staticFramework)
        XCTAssertEqual(
            configTarget.settings,
            expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        XCTAssertEqual(configTarget.sources.map(\.path), [configPath])
        XCTAssertEqual(configTarget.filesGroup, .group(name: projectName))
        XCTAssertEmpty(configTarget.dependencies)

        // Generated Project
        XCTAssertEqual(project.path, sourceRootPath.appending(component: projectName))
        XCTAssertEqual(project.name, projectName)
        XCTAssertEqual(project.settings, Settings(
            base: [:],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        ))
        XCTAssertEqual(project.filesGroup, .group(name: projectName))

        // Generated Scheme
        XCTAssertEqual(project.schemes.count, 1)
        let scheme = try XCTUnwrap(project.schemes.first)
        XCTAssertEqual(scheme.name, projectName)

        let buildAction = try XCTUnwrap(scheme.buildAction)
        XCTAssertEqual(buildAction.targets.map(\.name).sorted(), targets.map(\.name).sorted())

        let runAction = try XCTUnwrap(scheme.runAction)
        XCTAssertEqual(runAction.filePath, tuistPath)
        let generateArgument = "generate --path \(sourceRootPath)"
        XCTAssertEqual(runAction.arguments, Arguments(launchArguments: [LaunchArgument(name: generateArgument, isEnabled: true)]))
    }

    func test_tuist_edit_with_one_plugin_no_projects() async throws {
        let sourceRootPath = try temporaryPath()
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

        let project = try XCTUnwrap(graph.projects.values.first)
        let targets = graph.projects.values.flatMap(\.targets.values).sorted(by: { $0.name < $1.name })

        // Then
        XCTAssertEqual(targets.count, 1)
        XCTAssertEmpty(targets.flatMap(\.dependencies))

        // Generated Plugin target
        let pluginTarget = try XCTUnwrap(project.targets.values.sorted().last(where: { $0.name == sourceRootPath.basename }))

        XCTAssertEqual(pluginTarget.destinations, .macOS)
        XCTAssertEqual(pluginTarget.product, .staticFramework)
        XCTAssertEqual(
            pluginTarget.settings,
            expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        XCTAssertEqual(pluginTarget.sources.map(\.path), pluginManifestPaths)
        XCTAssertEqual(pluginTarget.filesGroup, projectsGroup)
        XCTAssertEmpty(pluginTarget.dependencies)

        // Generated Project
        XCTAssertEqual(project.path, sourceRootPath.appending(component: projectName))
        XCTAssertEqual(project.name, projectName)
        XCTAssertEqual(project.settings, Settings(
            base: [:],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        ))
        XCTAssertEqual(project.filesGroup, projectsGroup)

        // Generated Schemes
        XCTAssertEqual(project.schemes.count, 2)
        let schemes = project.schemes
        XCTAssertEqual(schemes.map(\.name).sorted(), [pluginTarget.name, "Plugins"].sorted())

        let pluginBuildAction = try XCTUnwrap(schemes.first?.buildAction)
        XCTAssertEqual(pluginBuildAction.targets.map(\.name), [pluginTarget.name])

        let allPluginsBuildAction = try XCTUnwrap(schemes.last?.buildAction)
        XCTAssertEqual(allPluginsBuildAction.targets.map(\.name).sorted(), targets.map(\.name).sorted())
    }

    func test_tuist_edit_with_more_than_one_plugin_no_projects() async throws {
        let sourceRootPath = try temporaryPath()
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

        let project = try XCTUnwrap(graph.projects.values.first)
        let targets = graph.projects.values.flatMap(\.targets.values).sorted(by: { $0.name < $1.name })

        // Then
        XCTAssertEqual(targets.count, 2)
        XCTAssertEmpty(targets.flatMap(\.dependencies))

        // Generated first plugin target
        let firstPluginTarget = try XCTUnwrap(project.targets.values.sorted().last(where: { $0.name == "A" }))

        XCTAssertEqual(firstPluginTarget.destinations, .macOS)
        XCTAssertEqual(firstPluginTarget.product, .staticFramework)
        XCTAssertEqual(
            firstPluginTarget.settings,
            expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        XCTAssertEqual(firstPluginTarget.sources.map(\.path), [pluginManifestPaths[0]])
        XCTAssertEqual(firstPluginTarget.filesGroup, projectsGroup)
        XCTAssertEmpty(firstPluginTarget.dependencies)

        // Generated second plugin target
        let secondPluginTarget = try XCTUnwrap(project.targets.values.sorted().last(where: { $0.name == "B" }))

        XCTAssertEqual(secondPluginTarget.destinations, .macOS)
        XCTAssertEqual(secondPluginTarget.product, .staticFramework)
        XCTAssertEqual(
            secondPluginTarget.settings,
            expectedSettings(includePaths: [projectDescriptionPath, projectDescriptionPath.parentDirectory])
        )
        XCTAssertEqual(secondPluginTarget.sources.map(\.path), [pluginManifestPaths[1]])
        XCTAssertEqual(secondPluginTarget.filesGroup, projectsGroup)
        XCTAssertEmpty(secondPluginTarget.dependencies)

        // Generated Project
        XCTAssertEqual(project.path, sourceRootPath.appending(component: projectName))
        XCTAssertEqual(project.name, projectName)
        XCTAssertEqual(project.settings, Settings(
            base: [:],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        ))
        XCTAssertEqual(project.filesGroup, projectsGroup)

        // Generated Schemes
        let schemes = project.schemes.sorted(by: { $0.name < $1.name })
        XCTAssertEqual(project.schemes.count, 3)
        XCTAssertEqual(
            schemes.map(\.name),
            [firstPluginTarget.name, secondPluginTarget.name, "Plugins"].sorted()
        )

        let firstBuildAction = try XCTUnwrap(schemes[0].buildAction)
        XCTAssertEqual(
            firstBuildAction.targets.map(\.name),
            [firstPluginTarget].map(\.name)
        )

        let secondBuildAction = try XCTUnwrap(schemes[1].buildAction)
        XCTAssertEqual(secondBuildAction.targets.map(\.name), [secondPluginTarget].map(\.name))

        let pluginsBuildAction = try XCTUnwrap(schemes[2].buildAction)
        XCTAssertEqual(
            pluginsBuildAction.targets.map(\.name).sorted(),
            [firstPluginTarget, secondPluginTarget].map(\.name).sorted()
        )
    }

    func test_tuist_edit_plugin_only_takes_required_sources() async throws {
        // Given
        let sourceRootPath = try temporaryPath()
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
        try await createFiles([
            "Unrelated/Source.swift",
            "Source.swift",
            "ProjectDescriptionHelpers/data.json",
            "Templates/strings.stencil",
        ])
        let helperSources = try await createFiles([
            "ProjectDescriptionHelpers/HelperA.swift",
            "ProjectDescriptionHelpers/HelperB.swift",
        ])
        let templateSources = try await createFiles([
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
        let project = try XCTUnwrap(graph.projects.values.first)
        let pluginTarget = try XCTUnwrap(project.targets.values.first)

        XCTAssertEqual(
            pluginTarget.sources.sorted(by: { $0.path < $1.path }),
            ([pluginManifestPath] + helperSources + templateSources).map { SourceFile(path: $0) }
        )
    }

    func test_tuist_edit_project_with_plugin() async throws {
        // Given
        let sourceRootPath = try temporaryPath()
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

        let pluginsProject = try XCTUnwrap(graph.projects.values.first(where: { $0.name == pluginsProjectName }))
        let manifestsProject = try XCTUnwrap(graph.projects.values.first(where: { $0.name == manifestsProjectName }))
        let targets = graph.projects.values.flatMap(\.targets.values).sorted(by: { $0.name < $1.name })
        let localPluginTarget = try XCTUnwrap(targets.first(where: { $0.name == "ALocalPlugin" }))
        let helpersTarget = try XCTUnwrap(targets.first(where: { $0.name == "ProjectDescriptionHelpers" }))
        let manifestsTarget = try XCTUnwrap(targets.first(where: { $0 != localPluginTarget && $0 != helpersTarget }))

        // Then
        XCTAssertEqual(targets.count, 3)

        // Local plugin target
        XCTAssertEqual(localPluginTarget.destinations, .macOS)
        XCTAssertEqual(localPluginTarget.product, .staticFramework)
        XCTAssertEqual(localPluginTarget.sources.map(\.path).first?.parentDirectory, localPlugin.path)
        XCTAssertEqual(localPluginTarget.filesGroup, pluginsGroup)
        XCTAssertEmpty(localPluginTarget.dependencies)
        XCTAssertEqual(
            localPluginTarget.settings,
            expectedSettings(includePaths: [
                projectDescriptionPath,
                projectDescriptionPath.parentDirectory,
            ])
        )

        // ProjectDescriptionHelpers target
        XCTAssertEqual(helpersTarget.destinations, .macOS)
        XCTAssertEqual(helpersTarget.product, .staticFramework)
        XCTAssertEqual(helpersTarget.sources.map(\.path).first, helperPaths.first)
        XCTAssertEqual(helpersTarget.filesGroup, projectsGroup)
        // Helpers can depend on local editable plugins
        XCTAssertEqual(helpersTarget.dependencies, [
            .target(name: localPluginTarget.name),
        ])
        XCTAssertEqual(
            helpersTarget.settings,
            expectedSettings(includePaths: [
                projectDescriptionPath,
                projectDescriptionPath.parentDirectory,
                // Helpers can include pre-built remote plugins
                remotePlugin.path.parentDirectory,
            ])
        )

        // Generated Manifests target
        XCTAssertEqual(manifestsTarget.destinations, .macOS)
        XCTAssertEqual(manifestsTarget.product, .staticFramework)
        XCTAssertEqual(manifestsTarget.sources.map(\.path), projectManifestPaths)
        XCTAssertEqual(manifestsTarget.filesGroup, projectsGroup)
        XCTAssertEqual(
            manifestsTarget.dependencies,
            [
                .target(name: "ProjectDescriptionHelpers"),
                .target(name: "ALocalPlugin"),
            ]
        )
        XCTAssertEqual(
            manifestsTarget.settings,
            expectedSettings(includePaths: [
                projectDescriptionPath,
                projectDescriptionPath.parentDirectory,
                // Manifests can include plugins
                remotePlugin.path.parentDirectory,
            ])
        )

        // Generated manifests Project
        let manifestsScheme = try XCTUnwrap(manifestsProject.schemes.first)
        let manifestsBuildAction = try XCTUnwrap(manifestsScheme.buildAction)
        let manifestsRunAction = try XCTUnwrap(manifestsScheme.runAction)
        XCTAssertEqual(manifestsProject.path, sourceRootPath.appending(component: manifestsProjectName))
        XCTAssertEqual(manifestsProject.name, manifestsProjectName)
        XCTAssertEqual(manifestsProject.settings, Settings(
            base: [:],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        ))
        XCTAssertEqual(manifestsProject.filesGroup, projectsGroup)
        XCTAssertEqual(manifestsProject.schemes.count, 1)
        XCTAssertEqual(manifestsScheme.name, manifestsProjectName)
        XCTAssertEqual(
            manifestsBuildAction.targets.map(\.name).sorted(),
            [manifestsTarget.name, "ProjectDescriptionHelpers"].sorted()
        )
        XCTAssertEqual(manifestsRunAction.filePath, tuistPath)
        XCTAssertEqual(
            manifestsRunAction.arguments,
            Arguments(launchArguments: [LaunchArgument(name: "generate --path \(sourceRootPath)", isEnabled: true)])
        )

        // Generated plugins project for local plugins
        let schemes = pluginsProject.schemes
        let aLocalPluginScheme = try XCTUnwrap(schemes.first(where: { $0.name == "ALocalPlugin" }))
        let pluginsScheme = try XCTUnwrap(schemes.first(where: { $0.name == pluginsProjectName }))
        XCTAssertEqual(pluginsProject.path, sourceRootPath.appending(component: pluginsProjectName))
        XCTAssertEqual(pluginsProject.name, pluginsProjectName)
        XCTAssertEqual(pluginsProject.settings, Settings(
            base: [:],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        ))
        XCTAssertEqual(pluginsProject.filesGroup, pluginsGroup)
        XCTAssertEqual(pluginsProject.schemes.count, 2)
        XCTAssertEqual(aLocalPluginScheme.buildAction?.targets.map(\.name).sorted(), [localPlugin.name])
        XCTAssertEqual(pluginsScheme.buildAction?.targets.map(\.name).sorted(), [localPlugin.name])
    }

    fileprivate func expectedSettings(includePaths: [AbsolutePath]) -> Settings {
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
