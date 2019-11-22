import Basic
import Foundation
import TuistCore
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
        super.tearDown()
        subject = nil
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
        let manifestsTarget = project.targets.first
        let helpersTarget = project.targets.last

        XCTAssertEqual(project.name, "Manifests")
        XCTAssertEqual(project.filesGroup, .group(name: "Manifests"))

        XCTAssertEqual(manifestsTarget?.name, "Manifests")
        XCTAssertEqual(manifestsTarget?.platform, .macOS)
        XCTAssertEqual(manifestsTarget?.product, .staticFramework)
        XCTAssertEqual(manifestsTarget?.bundleId, "io.tuist.${PRODUCT_NAME:rfc1034identifier}")
        XCTAssertEqual(manifestsTarget?.sources.map { $0.path }, manifestPaths)
        XCTAssertEqual(manifestsTarget?.filesGroup, .group(name: "Manifests"))
        XCTAssertEqual(manifestsTarget?.dependencies, [.target(name: "ProjectDescriptionHelpers")])

        XCTAssertEqual(helpersTarget?.name, "ProjectDescriptionHelpers")
        XCTAssertEqual(helpersTarget?.platform, .macOS)
        XCTAssertEqual(helpersTarget?.product, .staticFramework)
        XCTAssertEqual(helpersTarget?.bundleId, "io.tuist.${PRODUCT_NAME:rfc1034identifier}")
        XCTAssertEqual(helpersTarget?.sources.map { $0.path }, helperPaths)
        XCTAssertEqual(helpersTarget?.filesGroup, .group(name: "Manifests"))
        XCTAssertEqual(helpersTarget?.dependencies, [])

        let targetNodes = graph.targets.sorted(by: { $0.target.name < $1.target.name })
        XCTAssertEqual(targetNodes.count, 2)
        XCTAssertEqual(targetNodes.first?.target, manifestsTarget)
        XCTAssertEqual(targetNodes.last?.target, helpersTarget)
        XCTAssertEqual(targetNodes.first?.dependencies, [targetNodes.last!])
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
        let manifestsTarget = project.targets.first
        XCTAssertEqual(project.targets.count, 1)

        XCTAssertEqual(project.name, "Manifests")
        XCTAssertEqual(project.filesGroup, .group(name: "Manifests"))

        XCTAssertEqual(manifestsTarget?.name, "Manifests")
        XCTAssertEqual(manifestsTarget?.platform, .macOS)
        XCTAssertEqual(manifestsTarget?.product, .staticFramework)
        XCTAssertEqual(manifestsTarget?.bundleId, "io.tuist.${PRODUCT_NAME:rfc1034identifier}")
        XCTAssertEqual(manifestsTarget?.sources.map { $0.path }, manifestPaths)
        XCTAssertEqual(manifestsTarget?.filesGroup, .group(name: "Manifests"))
        XCTAssertEqual(manifestsTarget?.dependencies, [])

        let targetNodes = graph.targets.sorted(by: { $0.target.name < $1.target.name })
        XCTAssertEqual(targetNodes.count, 1)
        XCTAssertEqual(targetNodes.first?.target, manifestsTarget)
        XCTAssertEqual(targetNodes.first?.dependencies, [])
    }
}
