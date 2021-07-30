import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class ProjectEditorMapperTests: TuistUnitTestCase {
    var subject: ProjectEditorMapper!

    override func setUp() {
        super.setUp()
        system.swiftVersionStub = { "5.2" }
        developerEnvironment.stubbedArchitecture = .arm64
        subject = ProjectEditorMapper()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_edit_when_there_are_helpers_and_setup_and_config_and_dependencies_and_tasks() throws {
        // Given
        let sourceRootPath = try temporaryPath()
        let projectManifestPaths = [sourceRootPath].map { $0.appending(component: "Project.swift") }
        let setupPath = sourceRootPath.appending(component: "Setup.swift")
        let configPath = sourceRootPath.appending(components: Constants.tuistDirectoryName, "Config.swift")
        let dependenciesPath = sourceRootPath.appending(components: Constants.tuistDirectoryName, "Dependencies.swift")
        let helperPaths = [sourceRootPath].map { $0.appending(component: "Project+Template.swift") }
        let templates = [sourceRootPath].map { $0.appending(component: "template") }
        let projectDescriptionPath = sourceRootPath.appending(component: "ProjectDescription.framework")
        let tuistPath = AbsolutePath("/usr/bin/foo/bar/tuist")
        let projectName = "Manifests"
        let projectsGroup = ProjectGroup.group(name: projectName)
        let tasksPaths = [
            sourceRootPath.appending(component: "TaskOne.swift"),
            sourceRootPath.appending(component: "TaskTwo.swift"),
        ]

        // When
        let graph = try subject.map(
            name: "TestManifests",
            tuistPath: tuistPath,
            sourceRootPath: sourceRootPath,
            destinationDirectory: sourceRootPath,
            setupPath: setupPath,
            configPath: configPath,
            dependenciesPath: dependenciesPath,
            projectManifests: projectManifestPaths,
            editablePluginManifests: [],
            pluginProjectDescriptionHelpersModule: [],
            helpers: helperPaths,
            templates: templates,
            tasks: tasksPaths,
            projectDescriptionPath: projectDescriptionPath,
            projectAutomationPath: sourceRootPath.appending(component: "ProjectAutomation.framework")
        )

        let project = try XCTUnwrap(graph.projects.values.first)

        let targets = graph.targets.values.lazy
            .flatMap(\.values)
            .sorted(by: { $0.name < $1.name })

        // Then
        XCTAssertEqual(graph.name, "TestManifests")

        XCTAssertEqual(targets.count, 8)
        XCTAssertEqual(project.targets.sorted { $0.name < $1.name }, targets)

        // Generated Manifests target
        let manifestsTarget = try XCTUnwrap(project.targets.first(where: { $0.name == sourceRootPath.basename + projectName }))
        XCTAssertEqual(targets.last, manifestsTarget)

        XCTAssertEqual(manifestsTarget.platform, .macOS)
        XCTAssertEqual(manifestsTarget.product, .staticFramework)
        XCTAssertEqual(manifestsTarget.settings, expectedSettings(includePaths: [sourceRootPath, sourceRootPath.parentDirectory]))
        XCTAssertEqual(manifestsTarget.sources.map(\.path), projectManifestPaths)
        XCTAssertEqual(manifestsTarget.filesGroup, projectsGroup)
        XCTAssertEqual(manifestsTarget.dependencies, [.target(name: "ProjectDescriptionHelpers")])

        // Generated Helpers target
        let helpersTarget = try XCTUnwrap(project.targets.last(where: { $0.name == "ProjectDescriptionHelpers" }))
        XCTAssertTrue(targets.contains(helpersTarget))

        XCTAssertEqual(helpersTarget.name, "ProjectDescriptionHelpers")
        XCTAssertEqual(helpersTarget.platform, .macOS)
        XCTAssertEqual(helpersTarget.product, .staticFramework)
        XCTAssertEqual(helpersTarget.settings, expectedSettings(includePaths: [sourceRootPath, sourceRootPath.parentDirectory]))
        XCTAssertEqual(helpersTarget.sources.map(\.path), helperPaths)
        XCTAssertEqual(helpersTarget.filesGroup, projectsGroup)
        XCTAssertEmpty(helpersTarget.dependencies)

        // Generated Templates target
        let templatesTarget = try XCTUnwrap(project.targets.last(where: { $0.name == "Templates" }))
        XCTAssertTrue(targets.contains(templatesTarget))

        XCTAssertEqual(templatesTarget.name, "Templates")
        XCTAssertEqual(templatesTarget.platform, .macOS)
        XCTAssertEqual(templatesTarget.product, .staticFramework)
        XCTAssertEqual(templatesTarget.settings, expectedSettings(includePaths: [sourceRootPath, sourceRootPath.parentDirectory]))
        XCTAssertEqual(templatesTarget.sources.map(\.path), templates)
        XCTAssertEqual(templatesTarget.filesGroup, projectsGroup)
        XCTAssertEmpty(templatesTarget.dependencies)

        // Generated Setup target
        let setupTarget = try XCTUnwrap(project.targets.last(where: { $0.name == "Setup" }))
        XCTAssertTrue(targets.contains(setupTarget))

        XCTAssertEqual(setupTarget.name, "Setup")
        XCTAssertEqual(setupTarget.platform, .macOS)
        XCTAssertEqual(setupTarget.product, .staticFramework)
        XCTAssertEqual(setupTarget.settings, expectedSettings(includePaths: [sourceRootPath, sourceRootPath.parentDirectory]))
        XCTAssertEqual(setupTarget.sources.map(\.path), [setupPath])
        XCTAssertEqual(setupTarget.filesGroup, projectsGroup)
        XCTAssertEmpty(setupTarget.dependencies)

        // Generated Config target
        let configTarget = try XCTUnwrap(project.targets.last(where: { $0.name == "Config" }))
        XCTAssertTrue(targets.contains(configTarget))

        XCTAssertEqual(configTarget.name, "Config")
        XCTAssertEqual(configTarget.platform, .macOS)
        XCTAssertEqual(configTarget.product, .staticFramework)
        XCTAssertEqual(configTarget.settings, expectedSettings(includePaths: [sourceRootPath, sourceRootPath.parentDirectory]))
        XCTAssertEqual(configTarget.sources.map(\.path), [configPath])
        XCTAssertEqual(configTarget.filesGroup, projectsGroup)
        XCTAssertEmpty(configTarget.dependencies)

        // Generated Dependencies target
        let dependenciesTarget = try XCTUnwrap(project.targets.last(where: { $0.name == "Dependencies" }))
        XCTAssertTrue(targets.contains(dependenciesTarget))

        XCTAssertEqual(dependenciesTarget.name, "Dependencies")
        XCTAssertEqual(dependenciesTarget.platform, .macOS)
        XCTAssertEqual(dependenciesTarget.product, .staticFramework)
        XCTAssertEqual(dependenciesTarget.settings, expectedSettings(includePaths: [sourceRootPath, sourceRootPath.parentDirectory]))
        XCTAssertEqual(dependenciesTarget.sources.map(\.path), [dependenciesPath])
        XCTAssertEqual(dependenciesTarget.filesGroup, projectsGroup)
        XCTAssertEmpty(dependenciesTarget.dependencies)

        // Generated TaskOne target
        let taskOneTarget = try XCTUnwrap(project.targets.last(where: { $0.name == "TaskOne" }))
        XCTAssertTrue(targets.contains(taskOneTarget))

        XCTAssertEqual(taskOneTarget.name, "TaskOne")
        XCTAssertEqual(taskOneTarget.platform, .macOS)
        XCTAssertEqual(taskOneTarget.product, .staticFramework)
        XCTAssertEqual(taskOneTarget.settings, expectedSettings(includePaths: [sourceRootPath, sourceRootPath.parentDirectory]))
        XCTAssertEqual(taskOneTarget.sources.map(\.path), [tasksPaths[0]])
        XCTAssertEqual(taskOneTarget.filesGroup, projectsGroup)
        XCTAssertEmpty(taskOneTarget.dependencies)

        // Generated TaskTwo target
        let taskTwoTarget = try XCTUnwrap(project.targets.last(where: { $0.name == "TaskTwo" }))
        XCTAssertTrue(targets.contains(taskTwoTarget))

        XCTAssertEqual(taskTwoTarget.name, "TaskTwo")
        XCTAssertEqual(taskTwoTarget.platform, .macOS)
        XCTAssertEqual(taskTwoTarget.product, .staticFramework)
        XCTAssertEqual(taskTwoTarget.settings, expectedSettings(includePaths: [sourceRootPath, sourceRootPath.parentDirectory]))
        XCTAssertEqual(taskTwoTarget.sources.map(\.path), [tasksPaths[1]])
        XCTAssertEqual(taskTwoTarget.filesGroup, projectsGroup)
        XCTAssertEmpty(taskTwoTarget.dependencies)

        // Generated Project
        XCTAssertEqual(project.path, sourceRootPath.appending(component: projectName))
        XCTAssertEqual(project.name, projectName)
        XCTAssertEqual(project.settings, Settings(
            base: ["ONLY_ACTIVE_ARCH": "NO",
                   "EXCLUDED_ARCHS": "x86_64"],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        ))
        XCTAssertEqual(project.filesGroup, projectsGroup)

        // Generated Scheme
        XCTAssertEqual(project.schemes.count, 1)
        let scheme = try XCTUnwrap(project.schemes.first)
        XCTAssertEqual(scheme.name, projectName)

        let buildAction = try XCTUnwrap(scheme.buildAction)
        XCTAssertEqual(buildAction.targets.lazy.map(\.name).sorted(), targets.map(\.name))

        let runAction = try XCTUnwrap(scheme.runAction)
        XCTAssertEqual(runAction.filePath, tuistPath)
        let generateArgument = "generate --path \(sourceRootPath)"
        XCTAssertEqual(runAction.arguments, Arguments(launchArguments: [LaunchArgument(name: generateArgument, isEnabled: true)]))
    }

    func test_edit_when_there_are_no_helpers_and_no_setup_and_no_config_and_no_dependencies() throws {
        // Given
        let sourceRootPath = try temporaryPath()
        let projectManifestPaths = [sourceRootPath].map { $0.appending(component: "Project.swift") }
        let helperPaths: [AbsolutePath] = []
        let templates: [AbsolutePath] = []
        let projectDescriptionPath = sourceRootPath.appending(component: "ProjectDescription.framework")
        let tuistPath = AbsolutePath("/usr/bin/foo/bar/tuist")
        let projectName = "Manifests"
        let projectsGroup = ProjectGroup.group(name: projectName)

        // When
        let graph = try subject.map(
            name: "TestManifests",
            tuistPath: tuistPath,
            sourceRootPath: sourceRootPath,
            destinationDirectory: sourceRootPath,
            setupPath: nil,
            configPath: nil,
            dependenciesPath: nil,
            projectManifests: projectManifestPaths,
            editablePluginManifests: [],
            pluginProjectDescriptionHelpersModule: [],
            helpers: helperPaths,
            templates: templates,
            tasks: [],
            projectDescriptionPath: projectDescriptionPath,
            projectAutomationPath: sourceRootPath.appending(component: "ProjectAutomation.framework")
        )

        let project = try XCTUnwrap(graph.projects.values.first)

        let targets = graph.targets.values.lazy
            .flatMap(\.values)
            .sorted(by: { $0.name < $1.name })

        // Then
        XCTAssertEqual(targets.count, 1)
        XCTAssertEmpty(targets.flatMap(\.dependencies))

        // Generated Manifests target
        let manifestsTarget = try XCTUnwrap(project.targets.last(where: { $0.name == sourceRootPath.basename + projectName }))

        XCTAssertEqual(manifestsTarget.platform, .macOS)
        XCTAssertEqual(manifestsTarget.product, .staticFramework)
        XCTAssertEqual(manifestsTarget.settings, expectedSettings(includePaths: [sourceRootPath, sourceRootPath.parentDirectory]))
        XCTAssertEqual(manifestsTarget.sources.map(\.path), projectManifestPaths)
        XCTAssertEqual(manifestsTarget.filesGroup, projectsGroup)
        XCTAssertEmpty(manifestsTarget.dependencies)

        // Generated Project
        XCTAssertEqual(project.path, sourceRootPath.appending(component: projectName))
        XCTAssertEqual(project.name, projectName)
        XCTAssertEqual(project.settings, Settings(
            base: ["ONLY_ACTIVE_ARCH": "NO",
                   "EXCLUDED_ARCHS": "x86_64"],
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

    func test_tuist_edit_with_more_than_one_manifest() throws {
        // Given
        let sourceRootPath = try temporaryPath()
        let setupPath = sourceRootPath.appending(component: "Setup.swift")
        let configPath = sourceRootPath.appending(components: Constants.tuistDirectoryName, "Config.swift")
        let dependenciesPath = sourceRootPath.appending(components: Constants.tuistDirectoryName, "Dependencies.swift")
        let otherProjectPath = "Module"
        let projectManifestPaths = [
            sourceRootPath.appending(component: "Project.swift"),
            sourceRootPath.appending(component: otherProjectPath).appending(component: "Project.swift"),
        ]
        let helperPaths: [AbsolutePath] = []
        let templates: [AbsolutePath] = []
        let projectDescriptionPath = sourceRootPath.appending(component: "ProjectDescription.framework")
        let tuistPath = AbsolutePath("/usr/bin/foo/bar/tuist")
        let projectName = "Manifests"

        // When
        let graph = try subject.map(
            name: "TestManifests",
            tuistPath: tuistPath,
            sourceRootPath: sourceRootPath,
            destinationDirectory: sourceRootPath,
            setupPath: setupPath,
            configPath: configPath,
            dependenciesPath: dependenciesPath,
            projectManifests: projectManifestPaths,
            editablePluginManifests: [],
            pluginProjectDescriptionHelpersModule: [],
            helpers: helperPaths,
            templates: templates,
            tasks: [],
            projectDescriptionPath: projectDescriptionPath,
            projectAutomationPath: sourceRootPath.appending(component: "ProjectAutomation.framework")
        )

        let project = try XCTUnwrap(graph.projects.values.first)

        let targets = graph.targets.values.lazy
            .flatMap(\.values)
            .sorted(by: { $0.name < $1.name })

        // Then

        XCTAssertEqual(targets.count, 5)
        XCTAssertEmpty(targets.flatMap(\.dependencies))

        // Generated Manifests target
        let manifestOneTarget = try XCTUnwrap(project.targets.last(where: { $0.name == "ModuleManifests" }))

        XCTAssertEqual(manifestOneTarget.name, "ModuleManifests")
        XCTAssertEqual(manifestOneTarget.platform, .macOS)
        XCTAssertEqual(manifestOneTarget.product, .staticFramework)
        XCTAssertEqual(manifestOneTarget.settings, expectedSettings(includePaths: [sourceRootPath, sourceRootPath.parentDirectory]))
        XCTAssertEqual(manifestOneTarget.sources.map(\.path), [try XCTUnwrap(projectManifestPaths.last)])
        XCTAssertEqual(manifestOneTarget.filesGroup, .group(name: projectName))
        XCTAssertEmpty(manifestOneTarget.dependencies)

        // Generated Manifests target
        let manifestTwoTarget = try XCTUnwrap(project.targets.last(where: { $0.name == "\(sourceRootPath.basename)Manifests" }))

        XCTAssertEqual(manifestTwoTarget.platform, .macOS)
        XCTAssertEqual(manifestTwoTarget.product, .staticFramework)
        XCTAssertEqual(manifestTwoTarget.settings, expectedSettings(includePaths: [sourceRootPath, sourceRootPath.parentDirectory]))
        XCTAssertEqual(manifestTwoTarget.sources.map(\.path), [try XCTUnwrap(projectManifestPaths.first)])
        XCTAssertEqual(manifestTwoTarget.filesGroup, .group(name: projectName))
        XCTAssertEmpty(manifestTwoTarget.dependencies)

        // Generated Setup target
        let setupTarget = try XCTUnwrap(project.targets.last(where: { $0.name == "Setup" }))

        XCTAssertEqual(setupTarget.name, "Setup")
        XCTAssertEqual(setupTarget.platform, .macOS)
        XCTAssertEqual(setupTarget.product, .staticFramework)
        XCTAssertEqual(setupTarget.settings, expectedSettings(includePaths: [sourceRootPath, sourceRootPath.parentDirectory]))
        XCTAssertEqual(setupTarget.sources.map(\.path), [setupPath])
        XCTAssertEqual(setupTarget.filesGroup, .group(name: projectName))
        XCTAssertEmpty(setupTarget.dependencies)

        // Generated Config target
        let configTarget = try XCTUnwrap(project.targets.last(where: { $0.name == "Config" }))

        XCTAssertEqual(configTarget.name, "Config")
        XCTAssertEqual(configTarget.platform, .macOS)
        XCTAssertEqual(configTarget.product, .staticFramework)
        XCTAssertEqual(configTarget.settings, expectedSettings(includePaths: [sourceRootPath, sourceRootPath.parentDirectory]))
        XCTAssertEqual(configTarget.sources.map(\.path), [configPath])
        XCTAssertEqual(configTarget.filesGroup, .group(name: projectName))
        XCTAssertEmpty(configTarget.dependencies)

        // Generated Project
        XCTAssertEqual(project.path, sourceRootPath.appending(component: projectName))
        XCTAssertEqual(project.name, projectName)
        XCTAssertEqual(project.settings, Settings(
            base: ["ONLY_ACTIVE_ARCH": "NO",
                   "EXCLUDED_ARCHS": "x86_64"],
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

    func test_tuist_edit_with_one_plugin_no_projects() throws {
        let sourceRootPath = try temporaryPath()
        let pluginManifestPaths = [sourceRootPath].map { $0.appending(component: "Plugin.swift") }
        let editablePluginManifests = pluginManifestPaths.map {
            EditablePluginManifest(name: $0.parentDirectory.basename, path: $0.parentDirectory)
        }
        let helperPaths: [AbsolutePath] = []
        let templates: [AbsolutePath] = []
        let projectDescriptionPath = sourceRootPath.appending(component: "ProjectDescription.framework")
        let tuistPath = AbsolutePath("/usr/bin/foo/bar/tuist")
        let projectName = "Plugins"
        let projectsGroup = ProjectGroup.group(name: projectName)

        // When
        let graph = try subject.map(
            name: "TestManifests",
            tuistPath: tuistPath,
            sourceRootPath: sourceRootPath,
            destinationDirectory: sourceRootPath,
            setupPath: nil,
            configPath: nil,
            dependenciesPath: nil,
            projectManifests: [],
            editablePluginManifests: editablePluginManifests,
            pluginProjectDescriptionHelpersModule: [],
            helpers: helperPaths,
            templates: templates,
            tasks: [],
            projectDescriptionPath: projectDescriptionPath,
            projectAutomationPath: sourceRootPath.appending(component: "ProjectAutomation.framework")
        )

        let project = try XCTUnwrap(graph.projects.values.first)

        let targets = graph.targets.values.lazy
            .flatMap(\.values)
            .sorted(by: { $0.name < $1.name })

        // Then
        XCTAssertEqual(targets.count, 1)
        XCTAssertEmpty(targets.flatMap(\.dependencies))

        // Generated Plugin target
        let pluginTarget = try XCTUnwrap(project.targets.last(where: { $0.name == sourceRootPath.basename }))

        XCTAssertEqual(pluginTarget.platform, .macOS)
        XCTAssertEqual(pluginTarget.product, .staticFramework)
        XCTAssertEqual(pluginTarget.settings, expectedSettings(includePaths: [sourceRootPath, sourceRootPath.parentDirectory]))
        XCTAssertEqual(pluginTarget.sources.map(\.path), pluginManifestPaths)
        XCTAssertEqual(pluginTarget.filesGroup, projectsGroup)
        XCTAssertEmpty(pluginTarget.dependencies)

        // Generated Project
        XCTAssertEqual(project.path, sourceRootPath.appending(component: projectName))
        XCTAssertEqual(project.name, projectName)
        XCTAssertEqual(project.settings, Settings(
            base: ["ONLY_ACTIVE_ARCH": "NO",
                   "EXCLUDED_ARCHS": "x86_64"],
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

    func test_tuist_edit_with_more_than_one_plugin_no_projects() throws {
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
        let projectDescriptionPath = sourceRootPath.appending(component: "ProjectDescription.framework")
        let tuistPath = AbsolutePath("/usr/bin/foo/bar/tuist")
        let projectName = "Plugins"
        let projectsGroup = ProjectGroup.group(name: projectName)

        // When
        let graph = try subject.map(
            name: "TestManifests",
            tuistPath: tuistPath,
            sourceRootPath: sourceRootPath,
            destinationDirectory: sourceRootPath,
            setupPath: nil,
            configPath: nil,
            dependenciesPath: nil,
            projectManifests: [],
            editablePluginManifests: editablePluginManifests,
            pluginProjectDescriptionHelpersModule: [],
            helpers: helperPaths,
            templates: templates,
            tasks: [],
            projectDescriptionPath: projectDescriptionPath,
            projectAutomationPath: sourceRootPath.appending(component: "ProjectAutomation.framework")
        )

        let project = try XCTUnwrap(graph.projects.values.first)

        let targets = graph.targets.values.lazy
            .flatMap(\.values)
            .sorted(by: { $0.name < $1.name })

        // Then
        XCTAssertEqual(targets.count, 2)
        XCTAssertEmpty(targets.flatMap(\.dependencies))

        // Generated first plugin target
        let firstPluginTarget = try XCTUnwrap(project.targets.last(where: { $0.name == "A" }))

        XCTAssertEqual(firstPluginTarget.platform, .macOS)
        XCTAssertEqual(firstPluginTarget.product, .staticFramework)
        XCTAssertEqual(firstPluginTarget.settings, expectedSettings(includePaths: [sourceRootPath, sourceRootPath.parentDirectory]))
        XCTAssertEqual(firstPluginTarget.sources.map(\.path), [pluginManifestPaths[0]])
        XCTAssertEqual(firstPluginTarget.filesGroup, projectsGroup)
        XCTAssertEmpty(firstPluginTarget.dependencies)

        // Generated second plugin target
        let secondPluginTarget = try XCTUnwrap(project.targets.last(where: { $0.name == "B" }))

        XCTAssertEqual(secondPluginTarget.platform, .macOS)
        XCTAssertEqual(secondPluginTarget.product, .staticFramework)
        XCTAssertEqual(secondPluginTarget.settings, expectedSettings(includePaths: [sourceRootPath, sourceRootPath.parentDirectory]))
        XCTAssertEqual(secondPluginTarget.sources.map(\.path), [pluginManifestPaths[1]])
        XCTAssertEqual(secondPluginTarget.filesGroup, projectsGroup)
        XCTAssertEmpty(secondPluginTarget.dependencies)

        // Generated Project
        XCTAssertEqual(project.path, sourceRootPath.appending(component: projectName))
        XCTAssertEqual(project.name, projectName)
        XCTAssertEqual(project.settings, Settings(
            base: ["ONLY_ACTIVE_ARCH": "NO",
                   "EXCLUDED_ARCHS": "x86_64"],
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

    func test_tuist_edit_plugin_only_takes_required_sources() throws {
        // Given
        let sourceRootPath = try temporaryPath()
        let pluginManifestPath = sourceRootPath.appending(component: "Plugin.swift")
        let editablePluginManifests = [
            EditablePluginManifest(name: pluginManifestPath.parentDirectory.basename, path: pluginManifestPath.parentDirectory),
        ]
        let helperPaths: [AbsolutePath] = []
        let templates: [AbsolutePath] = []
        let projectDescriptionPath = sourceRootPath.appending(component: "ProjectDescription.framework")
        let tuistPath = AbsolutePath("/usr/bin/foo/bar/tuist")
        try createFiles([
            "Unrelated/Source.swift",
            "Source.swift",
            "ProjectDescriptionHelpers/data.json",
            "Templates/strings.stencil",
        ])
        let helperSources = try createFiles([
            "ProjectDescriptionHelpers/HelperA.swift",
            "ProjectDescriptionHelpers/HelperB.swift",
        ])
        let templateSources = try createFiles([
            "Templates/custom.swift",
            "Templates/strings.stencil",
        ])
        // When
        let graph = try subject.map(
            name: "TestManifests",
            tuistPath: tuistPath,
            sourceRootPath: sourceRootPath,
            destinationDirectory: sourceRootPath,
            setupPath: nil,
            configPath: nil,
            dependenciesPath: nil,
            projectManifests: [],
            editablePluginManifests: editablePluginManifests,
            pluginProjectDescriptionHelpersModule: [],
            helpers: helperPaths,
            templates: templates,
            tasks: [],
            projectDescriptionPath: projectDescriptionPath,
            projectAutomationPath: sourceRootPath.appending(component: "ProjectAutomation.framework")
        )

        // Then
        let project = try XCTUnwrap(graph.projects.values.first)
        let pluginTarget = try XCTUnwrap(project.targets.first)

        XCTAssertEqual(
            pluginTarget.sources,
            ([pluginManifestPath] + helperSources + templateSources).map { SourceFile(path: $0) }
        )
    }

    func test_tuist_edit_project_with_plugin() throws {
        // Given
        let sourceRootPath = try temporaryPath()
        let projectManifestPaths = [sourceRootPath].map { $0.appending(component: "Project.swift") }
        let helperPaths: [AbsolutePath] = []
        let templates: [AbsolutePath] = []
        let projectDescriptionPath = sourceRootPath.appending(component: "ProjectDescription.framework")
        let tuistPath = AbsolutePath("/usr/bin/foo/bar/tuist")
        let projectName = "Manifests"
        let projectsGroup = ProjectGroup.group(name: projectName)

        // When
        let pluginHelpersPath = AbsolutePath("/Path/To/Plugin/ProjectDescriptionHelpers")
        let graph = try subject.map(
            name: "TestManifests",
            tuistPath: tuistPath,
            sourceRootPath: sourceRootPath,
            destinationDirectory: sourceRootPath,
            setupPath: nil,
            configPath: nil,
            dependenciesPath: nil,
            projectManifests: projectManifestPaths,
            editablePluginManifests: [],
            pluginProjectDescriptionHelpersModule: [.init(name: "Plugin", path: pluginHelpersPath)],
            helpers: helperPaths,
            templates: templates,
            tasks: [],
            projectDescriptionPath: projectDescriptionPath,
            projectAutomationPath: sourceRootPath.appending(component: "ProjectAutomation.framework")
        )

        let project = try XCTUnwrap(graph.projects.values.first)

        let targets = graph.targets.values.lazy
            .flatMap(\.values)
            .sorted(by: { $0.name < $1.name })

        // Then
        XCTAssertEqual(targets.count, 1)
        XCTAssertEmpty(targets.flatMap(\.dependencies))

        // Generated Manifests target
        let manifestsTarget = try XCTUnwrap(project.targets.last(where: { $0.name == sourceRootPath.basename + projectName }))

        XCTAssertEqual(manifestsTarget.platform, .macOS)
        XCTAssertEqual(manifestsTarget.product, .staticFramework)
        XCTAssertEqual(manifestsTarget.settings, expectedSettings(includePaths: [sourceRootPath, sourceRootPath.parentDirectory, pluginHelpersPath.parentDirectory, pluginHelpersPath.parentDirectory.parentDirectory]))
        XCTAssertEqual(manifestsTarget.sources.map(\.path), projectManifestPaths)
        XCTAssertEqual(manifestsTarget.filesGroup, projectsGroup)
        XCTAssertEmpty(manifestsTarget.dependencies)

        // Generated Project
        XCTAssertEqual(project.path, sourceRootPath.appending(component: projectName))
        XCTAssertEqual(project.name, projectName)
        XCTAssertEqual(project.settings, Settings(
            base: ["ONLY_ACTIVE_ARCH": "NO",
                   "EXCLUDED_ARCHS": "x86_64"],
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
