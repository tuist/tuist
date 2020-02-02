import Basic
import Foundation
import TuistCore
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class ProjectEditorMapperTests: TuistUnitTestCase {
    var subject: ProjectEditorMapper!

    override func setUp() {
        super.setUp()
        subject = ProjectEditorMapper()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_edit_when_there_are_helpers() throws {
        // Given
        let sourceRootPath = try temporaryPath()
        let manifestPaths = [sourceRootPath].map { $0.appending(component: "Project.swift") }
        let helperPaths = [sourceRootPath].map { $0.appending(component: "Project+Template.swift") }
        let projectDescriptionPath = sourceRootPath.appending(component: "ProjectDescription.framework")

        // When
        let (project, graph) = subject.map(sourceRootPath: sourceRootPath,
                                           manifests: manifestPaths,
                                           helpers: helperPaths,
                                           projectDescriptionPath: projectDescriptionPath)

        // Then
        let targetNodes = graph.targets.sorted(by: { $0.target.name < $1.target.name })
        XCTAssertEqual(targetNodes.count, 2)
        XCTAssertEqual(targetNodes.first?.dependencies, [targetNodes.last!])

        // Generated Manifests target
        let manifestsTarget = try XCTUnwrap(project.targets.first)
        XCTAssertEqual(targetNodes.first?.target, manifestsTarget)

        XCTAssertEqual(manifestsTarget.name, "Manifests")
        XCTAssertEqual(manifestsTarget.platform, .macOS)
        XCTAssertEqual(manifestsTarget.product, .staticFramework)
        XCTAssertEqual(manifestsTarget.settings, expectedSettings(sourceRootPath: sourceRootPath))
        XCTAssertEqual(manifestsTarget.sources.map { $0.path }, manifestPaths)
        XCTAssertEqual(manifestsTarget.filesGroup, .group(name: "Manifests"))
        XCTAssertEqual(manifestsTarget.dependencies, [.target(name: "ProjectDescriptionHelpers")])

        // Generated Helpers target
        let helpersTarget = try XCTUnwrap(project.targets.last)
        XCTAssertEqual(targetNodes.last?.target, helpersTarget)

        XCTAssertEqual(helpersTarget.name, "ProjectDescriptionHelpers")
        XCTAssertEqual(helpersTarget.platform, .macOS)
        XCTAssertEqual(helpersTarget.product, .staticFramework)
        XCTAssertEqual(helpersTarget.settings, expectedSettings(sourceRootPath: sourceRootPath))
        XCTAssertEqual(helpersTarget.sources.map { $0.path }, helperPaths)
        XCTAssertEqual(helpersTarget.filesGroup, .group(name: "Manifests"))
        XCTAssertEqual(helpersTarget.dependencies, [])
        
        // Generated Project
        XCTAssertEqual(project.path, sourceRootPath)
        XCTAssertEqual(project.name, "Manifests")
        XCTAssertEqual(project.settings, Settings(base: [:],
                                                  configurations: Settings.default.configurations,
                                                  defaultSettings: .recommended))
        XCTAssertEqual(project.filesGroup, .group(name: "Manifests"))
        XCTAssertEqual(project.targets, targetNodes.map{ $0.target })
        
        // Generated Scheme
        XCTAssertEqual(project.schemes.count, 1)
        let scheme = try XCTUnwrap(project.schemes.first)
        XCTAssertEqual(scheme.name, "Manifests")
        
        let buildAction = try XCTUnwrap(scheme.buildAction)
        XCTAssertEqual(buildAction.targets.map { $0.name }, targetNodes.map { $0.name })
        
        let runAction = try XCTUnwrap(scheme.runAction)
        XCTAssertEqual(runAction.filePath, "/usr/local/bin/tuist")
        let generateArgument = "generate --path \(sourceRootPath)"
        XCTAssertEqual(runAction.arguments, Arguments(launch: [generateArgument : true]))
    }

    func test_edit_when_there_are_no_helpers() throws {
        // Given
        let sourceRootPath = try temporaryPath()
        let manifestPaths = [sourceRootPath].map { $0.appending(component: "Project.swift") }
        let helperPaths: [AbsolutePath] = []
        let projectDescriptionPath = sourceRootPath.appending(component: "ProjectDescription.framework")

        // When
        let (project, graph) = subject.map(sourceRootPath: sourceRootPath,
                                           manifests: manifestPaths,
                                           helpers: helperPaths,
                                           projectDescriptionPath: projectDescriptionPath)

        // Then
        let targetNodes = graph.targets.sorted(by: { $0.target.name < $1.target.name })
        XCTAssertEqual(targetNodes.count, 1)
        XCTAssertEqual(targetNodes.first?.dependencies, [])

        // Generated Manifests target
        let manifestsTarget = try XCTUnwrap(project.targets.first)
        XCTAssertEqual(targetNodes.first?.target, manifestsTarget)

        XCTAssertEqual(manifestsTarget.name, "Manifests")
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
                                                  defaultSettings: .recommended))
        XCTAssertEqual(project.filesGroup, .group(name: "Manifests"))
        XCTAssertEqual(project.targets, targetNodes.map{ $0.target })
        
        // Generated Scheme
        XCTAssertEqual(project.schemes.count, 1)
        let scheme = try XCTUnwrap(project.schemes.first)
        XCTAssertEqual(scheme.name, "Manifests")
        
        let buildAction = try XCTUnwrap(scheme.buildAction)
        XCTAssertEqual(buildAction.targets.map { $0.name }, targetNodes.map { $0.name })
        
        let runAction = try XCTUnwrap(scheme.runAction)
        XCTAssertEqual(runAction.filePath, "/usr/local/bin/tuist")
        let generateArgument = "generate --path \(sourceRootPath)"
        XCTAssertEqual(runAction.arguments, Arguments(launch: [generateArgument : true]))
    }

    fileprivate func expectedSettings(sourceRootPath: AbsolutePath) -> Settings {
        let base: [String: SettingValue] = [
            "FRAMEWORK_SEARCH_PATHS": .string(sourceRootPath.pathString),
            "LIBRARY_SEARCH_PATHS": .string(sourceRootPath.pathString),
            "SWIFT_INCLUDE_PATHS": .string(sourceRootPath.pathString),
            "SWIFT_VERSION": .string(Constants.swiftVersion),
        ]
        return Settings(base: base,
                        configurations: Settings.default.configurations,
                        defaultSettings: .recommended)
    }
}
