import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistAutomation
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class BuildGraphInspectorTests: TuistUnitTestCase {
    var subject: BuildGraphInspector!

    override func setUp() {
        super.setUp()
        subject = BuildGraphInspector()
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_buildArguments_when_macOS() throws {
        // Given
        let target = Target.test(platform: .macOS)

        // When
        let got = subject.buildArguments(target: target)

        // Then
        XCTAssertEqual(got, [
            .sdk(Platform.macOS.xcodeDeviceSDK),
        ])
    }

    func test_buildArguments_when_iOS() throws {
        // Given
        let target = Target.test(platform: .iOS)

        // When
        let got = subject.buildArguments(target: target)

        // Then
        XCTAssertEqual(got, [
            .sdk(Platform.iOS.xcodeSimulatorSDK!),
        ])
    }

    func test_buildArguments_when_watchOS() throws {
        // Given
        let target = Target.test(platform: .watchOS)

        // When
        let got = subject.buildArguments(target: target)

        // Then
        XCTAssertEqual(got, [
            .sdk(Platform.watchOS.xcodeSimulatorSDK!),
        ])
    }

    func test_buildArguments_when_tvOS() throws {
        // Given
        let target = Target.test(platform: .tvOS)

        // When
        let got = subject.buildArguments(target: target)

        // Then
        XCTAssertEqual(got, [
            .sdk(Platform.tvOS.xcodeSimulatorSDK!),
        ])
    }

    func test_buildableTarget() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let scheme = Scheme.test(buildAction: .test(targets: [.init(projectPath: projectPath, name: "Core")]))
        let target = Target.test(name: "Core")
        let project = Project.test(path: projectPath)
        let targetNode = TargetNode.test(project: project,
                                         target: target)
        let graph = Graph.test(targets: [projectPath: [targetNode]])

        // When
        let got = subject.buildableTarget(scheme: scheme, graph: graph)

        // Then
        XCTAssertEqual(got, target)
    }

    func test_buildableSchemes() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let scheme = Scheme.test(buildAction: .test(targets: [.init(projectPath: projectPath, name: "Core")]))
        let target = Target.test(name: "Core")
        let project = Project.test(path: projectPath, schemes: [scheme])
        let targetNode = TargetNode.test(project: project,
                                         target: target)
        let graph = Graph.test(entryNodes: [targetNode],
                               targets: [projectPath: [targetNode]])

        // When
        let got = subject.buildableSchemes(graph: graph)

        // Then
        XCTAssertEqual(got, [scheme])
    }

    func test_buildableSchemes_only_includes_entryTargets() throws {
        // Given
        let path = try temporaryPath()

        let projectAPath = path.appending(component: "ProjectA.xcodeproj")
        let schemeA = Scheme.test(buildAction: .test(targets: [.init(projectPath: projectAPath, name: "A")]))
        let projectA = Project.test(path: projectAPath, schemes: [schemeA])
        let targetA = Target.test(name: "A")
        let targetANode = TargetNode.test(project: projectA,
                                          target: targetA)

        let projectBPath = path.appending(component: "ProjectB.xcodeproj")
        let schemeB = Scheme.test(buildAction: .test(targets: [.init(projectPath: projectBPath, name: "B")]))
        let projectB = Project.test(path: projectBPath, schemes: [schemeB])
        let targetB = Target.test(name: "B")
        let targetBNode = TargetNode.test(project: projectB,
                                          target: targetB)

        let graph = Graph.test(entryNodes: [targetANode],
                               targets: [projectAPath: [targetANode], projectBPath: [targetBNode]])

        // When
        let got = subject.buildableSchemes(graph: graph)

        // Then
        XCTAssertEqual(got, [schemeA])
    }

    func test_workspacePath() throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        try FileHandler.shared.touch(workspacePath)

        // When
        let got = subject.workspacePath(directory: path)

        // Then
        XCTAssertEqual(got, workspacePath)
    }
}
