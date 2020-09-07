import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class ProjectEditorMapperTests: TuistUnitTestCase {
    var subject: ProjectEditorMapper!

    override func setUp() {
        super.setUp()
        system.swiftVersionStub = { "5.2" }
        subject = ProjectEditorMapper()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_edit_when_there_are_helpers() throws {
        // Given
        let sourceRootPath = try temporaryPath()
        let xcodeProjPath = sourceRootPath.appending(component: "Project.xcodeproj")
        let manifestPaths = [sourceRootPath].map { $0.appending(component: "Project.swift") }
        let helperPaths = [sourceRootPath].map { $0.appending(component: "Project+Template.swift") }
        let templates = [sourceRootPath].map { $0.appending(component: "template") }
        let projectDescriptionPath = sourceRootPath.appending(component: "ProjectDescription.framework")
        let tuistPath = AbsolutePath("/usr/bin/foo/bar/tuist")

        // When
        let (project, graph) = try subject.map(tuistPath: tuistPath,
                                               sourceRootPath: sourceRootPath,
                                               xcodeProjPath: xcodeProjPath,
                                               manifests: manifestPaths,
                                               helpers: helperPaths,
                                               templates: templates,
                                               projectDescriptionPath: projectDescriptionPath)

        // Then
        let targetNodes = graph.targets.values.lazy.flatMap { targets in targets.compactMap { $0 } }.sorted(by: { $0.target.name < $1.target.name })
        XCTAssertEqual(targetNodes.count, 3)
        XCTAssertEqual(targetNodes.last?.dependencies, Array(targetNodes.dropLast()))

        // Generated Manifests target
        let manifestsTarget = try XCTUnwrap(project.targets.first)
        XCTAssertEqual(targetNodes.last?.target, manifestsTarget)

        XCTAssertEqual(manifestsTarget.platform, .macOS)
        XCTAssertEqual(manifestsTarget.product, .staticFramework)
        XCTAssertEqual(manifestsTarget.settings, expectedSettings(sourceRootPath: sourceRootPath))
        XCTAssertEqual(manifestsTarget.sources.map { $0.path }, manifestPaths)
        XCTAssertEqual(manifestsTarget.filesGroup, .group(name: "Manifests"))
        XCTAssertEqual(manifestsTarget.dependencies, [.target(name: "ProjectDescriptionHelpers"), .target(name: "Templates")])

        // Generated Helpers target
        let helpersTarget = try XCTUnwrap(project.targets.last(where: { $0.name == "ProjectDescriptionHelpers" }))
        XCTAssertEqual(targetNodes.dropLast().first?.target, helpersTarget)

        XCTAssertEqual(helpersTarget.name, "ProjectDescriptionHelpers")
        XCTAssertEqual(helpersTarget.platform, .macOS)
        XCTAssertEqual(helpersTarget.product, .staticFramework)
        XCTAssertEqual(helpersTarget.settings, expectedSettings(sourceRootPath: sourceRootPath))
        XCTAssertEqual(helpersTarget.sources.map { $0.path }, helperPaths)
        XCTAssertEqual(helpersTarget.filesGroup, .group(name: "Manifests"))
        XCTAssertEqual(helpersTarget.dependencies, [])

        // Generated Templates target
        let templatesTarget = try XCTUnwrap(project.targets.last(where: { $0.name == "Templates" }))
        XCTAssertEqual(targetNodes.dropLast().last?.target, templatesTarget)

        XCTAssertEqual(templatesTarget.name, "Templates")
        XCTAssertEqual(templatesTarget.platform, .macOS)
        XCTAssertEqual(templatesTarget.product, .staticFramework)
        XCTAssertEqual(templatesTarget.settings, expectedSettings(sourceRootPath: sourceRootPath))
        XCTAssertEqual(templatesTarget.sources.map { $0.path }, templates)
        XCTAssertEqual(templatesTarget.filesGroup, .group(name: "Manifests"))
        XCTAssertEqual(templatesTarget.dependencies, [])

        // Generated Project
        XCTAssertEqual(project.path, sourceRootPath)
        XCTAssertEqual(project.name, "Manifests")
        XCTAssertEqual(project.settings, Settings(base: [:],
                                                  configurations: Settings.default.configurations,
                                                  defaultSettings: .recommended()))
        XCTAssertEqual(project.filesGroup, .group(name: "Manifests"))
        XCTAssertEqual(project.targets.sorted { $0.name < $1.name }, targetNodes.map { $0.target })

        // Generated Scheme
        XCTAssertEqual(project.schemes.count, 1)
        let scheme = try XCTUnwrap(project.schemes.first)
        XCTAssertEqual(scheme.name, "Manifests")

        let buildAction = try XCTUnwrap(scheme.buildAction)
        XCTAssertEqual(buildAction.targets.lazy.map { $0.name }.sorted(), targetNodes.map { $0.name })

        let runAction = try XCTUnwrap(scheme.runAction)
        XCTAssertEqual(runAction.filePath, tuistPath)
        let generateArgument = "generate --path \(sourceRootPath)"
        XCTAssertEqual(runAction.arguments, Arguments(launchArguments: [generateArgument: true]))
    }

    func test_edit_when_there_are_no_helpers() throws {
        // Given
        let sourceRootPath = try temporaryPath()
        let xcodeProjPath = sourceRootPath.appending(component: "Project.xcodeproj")
        let manifestPaths = [sourceRootPath].map { $0.appending(component: "Project.swift") }
        let helperPaths: [AbsolutePath] = []
        let templates: [AbsolutePath] = []
        let projectDescriptionPath = sourceRootPath.appending(component: "ProjectDescription.framework")
        let tuistPath = AbsolutePath("/usr/bin/foo/bar/tuist")

        // When
        let (project, graph) = try subject.map(tuistPath: tuistPath,
                                               sourceRootPath: sourceRootPath,
                                               xcodeProjPath: xcodeProjPath,
                                               manifests: manifestPaths,
                                               helpers: helperPaths,
                                               templates: templates,
                                               projectDescriptionPath: projectDescriptionPath)

        // Then
        let targetNodes = graph.targets.values.flatMap { targets in targets.compactMap { $0 } }.sorted(by: { $0.target.name < $1.target.name })
        XCTAssertEqual(targetNodes.count, 1)
        XCTAssertEqual(targetNodes.first?.dependencies, [])

        // Generated Manifests target
        let manifestsTarget = try XCTUnwrap(project.targets.first)
        XCTAssertEqual(targetNodes.first?.target, manifestsTarget)

        XCTAssertEqual(manifestsTarget.platform, .macOS)
        XCTAssertEqual(manifestsTarget.product, .staticFramework)
        XCTAssertEqual(manifestsTarget.settings, expectedSettings(sourceRootPath: sourceRootPath))
        XCTAssertEqual(manifestsTarget.sources.map { $0.path }, manifestPaths)
        XCTAssertEqual(manifestsTarget.filesGroup, .group(name: "Manifests"))
        XCTAssertEqual(manifestsTarget.dependencies, [])

        // Generated Project
        XCTAssertEqual(project.path, sourceRootPath)
        XCTAssertEqual(project.name, "Manifests")
        XCTAssertEqual(project.settings, Settings(base: [:],
                                                  configurations: Settings.default.configurations,
                                                  defaultSettings: .recommended()))
        XCTAssertEqual(project.filesGroup, .group(name: "Manifests"))
        XCTAssertEqual(project.targets, targetNodes.map { $0.target })

        // Generated Scheme
        XCTAssertEqual(project.schemes.count, 1)
        let scheme = try XCTUnwrap(project.schemes.first)
        XCTAssertEqual(scheme.name, "Manifests")

        let buildAction = try XCTUnwrap(scheme.buildAction)
        XCTAssertEqual(buildAction.targets.map { $0.name }, targetNodes.map { $0.name })

        let runAction = try XCTUnwrap(scheme.runAction)
        XCTAssertEqual(runAction.filePath, tuistPath)
        let generateArgument = "generate --path \(sourceRootPath)"
        XCTAssertEqual(runAction.arguments, Arguments(launchArguments: [generateArgument: true]))
    }

    func test_tuist_edit_with_more_than_one_manifest() throws {
        // Given
        let sourceRootPath = try temporaryPath()
        let xcodeProjPath = sourceRootPath.appending(component: "Project.xcodeproj")
        let otherProjectPath = "Module"
        let manifestPaths = [
            sourceRootPath.appending(component: "Project.swift"),
            sourceRootPath.appending(component: otherProjectPath).appending(component: "Project.swift"),
        ]
        let helperPaths: [AbsolutePath] = []
        let templates: [AbsolutePath] = []
        let projectDescriptionPath = sourceRootPath.appending(component: "ProjectDescription.framework")
        let tuistPath = AbsolutePath("/usr/bin/foo/bar/tuist")

        // When
        let (project, graph) = try subject.map(tuistPath: tuistPath,
                                               sourceRootPath: sourceRootPath,
                                               xcodeProjPath: xcodeProjPath,
                                               manifests: manifestPaths,
                                               helpers: helperPaths,
                                               templates: templates,
                                               projectDescriptionPath: projectDescriptionPath)

        // Then
        let targetNodes = graph.targets.values.flatMap { targets in targets.compactMap { $0 } }.sorted(by: { $0.target.name < $1.target.name })
        XCTAssertEqual(targetNodes.count, 2)
        XCTAssertEqual(targetNodes.first?.dependencies, [])
        XCTAssertEqual(targetNodes.last?.dependencies, [])

        // Generated Manifests target
        let manifestOneTarget = try XCTUnwrap(project.targets.first(where: { $0.name == "ModuleManifests" }))
        XCTAssertEqual(targetNodes.first?.target, manifestOneTarget)

        XCTAssertEqual(manifestOneTarget.name, "ModuleManifests")
        XCTAssertEqual(manifestOneTarget.platform, .macOS)
        XCTAssertEqual(manifestOneTarget.product, .staticFramework)
        XCTAssertEqual(manifestOneTarget.settings, expectedSettings(sourceRootPath: sourceRootPath))
        XCTAssertEqual(manifestOneTarget.sources.map { $0.path }, [manifestPaths.last])
        XCTAssertEqual(manifestOneTarget.filesGroup, .group(name: "Manifests"))
        XCTAssertEqual(manifestOneTarget.dependencies, [])

        // Generated Manifests target
        let manifestTwoTarget = try XCTUnwrap(project.targets.first(where: { $0.name != "ModuleManifests" }))
        XCTAssertEqual(targetNodes.last?.target, manifestTwoTarget)

        XCTAssertEqual(manifestTwoTarget.platform, .macOS)
        XCTAssertEqual(manifestTwoTarget.product, .staticFramework)
        XCTAssertEqual(manifestTwoTarget.settings, expectedSettings(sourceRootPath: sourceRootPath))
        XCTAssertEqual(manifestTwoTarget.sources.map { $0.path }, [manifestPaths.first])
        XCTAssertEqual(manifestTwoTarget.filesGroup, .group(name: "Manifests"))
        XCTAssertEqual(manifestTwoTarget.dependencies, [])

        // Generated Project
        XCTAssertEqual(project.path, sourceRootPath)
        XCTAssertEqual(project.name, "Manifests")
        XCTAssertEqual(project.settings, Settings(base: [:],
                                                  configurations: Settings.default.configurations,
                                                  defaultSettings: .recommended()))
        XCTAssertEqual(project.filesGroup, .group(name: "Manifests"))
        XCTAssertEqual(project.targets.sorted(by: { $0.name > $1.name }), targetNodes.map { $0.target }.sorted(by: { $0.name > $1.name }))

        // Generated Scheme
        XCTAssertEqual(project.schemes.count, 1)
        let scheme = try XCTUnwrap(project.schemes.first)
        XCTAssertEqual(scheme.name, "Manifests")

        let buildAction = try XCTUnwrap(scheme.buildAction)
        XCTAssertEqual(buildAction.targets.map { $0.name }.sorted(), targetNodes.map { $0.name }.sorted())

        let runAction = try XCTUnwrap(scheme.runAction)
        XCTAssertEqual(runAction.filePath, tuistPath)
        let generateArgument = "generate --path \(sourceRootPath)"
        XCTAssertEqual(runAction.arguments, Arguments(launchArguments: [generateArgument: true]))
    }

    fileprivate func expectedSettings(sourceRootPath: AbsolutePath) -> Settings {
        let base: [String: SettingValue] = [
            "FRAMEWORK_SEARCH_PATHS": .string(sourceRootPath.pathString),
            "LIBRARY_SEARCH_PATHS": .string(sourceRootPath.pathString),
            "SWIFT_INCLUDE_PATHS": .string(sourceRootPath.pathString),
            "SWIFT_VERSION": .string("5.2"),
        ]
        return Settings(base: base,
                        configurations: Settings.default.configurations,
                        defaultSettings: .recommended())
    }
}
