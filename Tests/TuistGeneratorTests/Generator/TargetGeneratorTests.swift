import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
import XcodeProj
import XCTest
@testable import TuistGenerator

final class TargetGeneratorTests: XCTestCase {
    var path: AbsolutePath!
    var subject: TargetGenerator!
    var pbxproj: PBXProj!
    var pbxProject: PBXProject!
    var fileElements: ProjectFileElements!

    override func setUp() {
        super.setUp()

        path = try! AbsolutePath(validating: "/test")
        pbxproj = PBXProj()
        pbxProject = createPbxProject(pbxproj: pbxproj)
        fileElements = ProjectFileElements([:])

        subject = TargetGenerator()
    }

    override func tearDown() {
        subject = nil
        fileElements = nil
        pbxProject = nil
        pbxproj = nil
        path = nil
        super.tearDown()
    }

    func test_generateTarget_productName() throws {
        // Given
        let target = Target.test(
            name: "MyFramework",
            product: .framework,
            scripts: [
                TargetScript(
                    name: "pre",
                    order: .pre,
                    script: .tool(path: "echo", args: ["pre1", "pre2"])
                ),
                TargetScript(
                    name: "post",
                    order: .post,
                    script: .tool(path: "echo", args: ["post1", "post2"]),
                    inputFileListPaths: ["/tmp/b"],
                    outputFileListPaths: ["/tmp/d"]
                ),
            ]
        )
        let project = Project.test(
            path: path,
            sourceRootPath: path,
            xcodeProjPath: path.appending(component: "Test.xcodeproj"),
            targets: [target]
        )
        let graph = Graph.test()
        let graphTraverser = GraphTraverser(graph: graph)
        let groups = ProjectGroups.generate(
            project: project,
            pbxproj: pbxproj
        )
        try fileElements.generateProjectFiles(
            project: project,
            graphTraverser: graphTraverser,
            groups: groups,
            pbxproj: pbxproj
        )

        // When
        let generatedTarget = try subject.generateTarget(
            target: target,
            project: project,
            pbxproj: pbxproj,
            pbxProject: pbxProject,
            projectSettings: Settings.test(),
            fileElements: fileElements,
            path: path,
            graphTraverser: graphTraverser
        )

        // Then
        XCTAssertEqual(generatedTarget.productName, "MyFramework")
        XCTAssertEqual(generatedTarget.productNameWithExtension(), "MyFramework.framework")
        XCTAssertEqual(generatedTarget.productType, .framework)

        guard let preBuildPhase = generatedTarget.buildPhases.first(where: { $0.name() == "pre" }),
              let postBuildPhase = generatedTarget.buildPhases.first(where: { $0.name() == "post" })
        else {
            XCTFail("Failed to generate target with build phases pre and post")
            return
        }

        XCTAssertEqual(preBuildPhase.inputFileListPaths, [])
        XCTAssertEqual(preBuildPhase.outputFileListPaths, [])

        XCTAssertEqual(postBuildPhase.inputFileListPaths, ["../tmp/b"])
        XCTAssertEqual(postBuildPhase.outputFileListPaths, ["../tmp/d"])
    }

    func test_generateTargetDependencies() throws {
        // Given
        let targetA = Target.test(name: "TargetA",
                                  destinations: [.mac, .iPhone])
        let targetB = Target.test(name: "TargetB",
                                  destinations: [.mac, .iPhone])
        let targetC = Target.test(name: "TargetC")
        let nativeTargetA = createNativeTarget(for: targetA)
        let nativeTargetB = createNativeTarget(for: targetB)
        let nativeTargetC = createNativeTarget(for: targetC)
        let graph = Graph.test(
            projects: [path: .test(path: path)],
            targets: [
                path: [
                    targetA.name: targetA,
                    targetB.name: targetB,
                    targetC.name: targetC,
                ],
            ],
            dependencies: [
                .target(name: targetA.name, path: path): [
                    .target(name: targetB.name, path: path),
                    .target(name: targetC.name, path: path)
                ],
            ],
            dependencyConditions: [
            GraphEdge(from: .target(name: targetA.name, path: path),
                      to: .target(name: targetC.name, path: path)) :
                    try XCTUnwrap(.when([.ios]))
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateTargetDependencies(
            path: path,
            targets: [targetA, targetB, targetC],
            nativeTargets: [
                "TargetA": nativeTargetA,
                "TargetB": nativeTargetB,
                "TargetC": nativeTargetC,
            ],
            graphTraverser: graphTraverser
        )

        // Then
        let expected: [PBXTargetDependency] = [
            PBXTargetDependency(name: "TargetB"),
            PBXTargetDependency(name: "TargetC", platformFilter: "ios"),
        ]

        for (index, dependency) in nativeTargetA.dependencies.enumerated() {
            XCTAssertEqual(dependency.name, expected[index].name)
            XCTAssertEqual(dependency.platformFilter, expected[index].platformFilter)
            XCTAssertEqual(dependency.platformFilters, expected[index].platformFilters)
        }
    }

    func test_generateTarget_actions() throws {
        // Given
        let graph = Graph.test()
        let graphTraverser = GraphTraverser(graph: graph)
        let target = Target.test(
            sources: [],
            resources: [],
            scripts: [
                TargetScript(
                    name: "post",
                    order: .post,
                    script: .scriptPath(path: path.appending(component: "script.sh"), args: ["arg"])
                ),
                TargetScript(
                    name: "pre",
                    order: .pre,
                    script: .scriptPath(path: path.appending(component: "script.sh"), args: ["arg"])
                ),
            ]
        )
        let project = Project.test(
            path: path,
            sourceRootPath: path,
            xcodeProjPath: path.appending(component: "Project.xcodeproj"),
            targets: [target]
        )
        let groups = ProjectGroups.generate(
            project: project,
            pbxproj: pbxproj
        )
        try fileElements.generateProjectFiles(
            project: project,
            graphTraverser: graphTraverser,
            groups: groups,
            pbxproj: pbxproj
        )

        // When
        let pbxTarget = try subject.generateTarget(
            target: target,
            project: project,
            pbxproj: pbxproj,
            pbxProject: pbxProject,
            projectSettings: Settings.test(),
            fileElements: fileElements,
            path: path,
            graphTraverser: graphTraverser
        )

        // Then
        let preBuildPhase = pbxTarget.buildPhases.first as? PBXShellScriptBuildPhase
        XCTAssertEqual(preBuildPhase?.name, "pre")
        XCTAssertEqual(preBuildPhase?.shellPath, "/bin/sh")
        XCTAssertEqual(preBuildPhase?.shellScript, "\"$SRCROOT\"/script.sh arg")

        let postBuildPhase = pbxTarget.buildPhases.last as? PBXShellScriptBuildPhase
        XCTAssertEqual(postBuildPhase?.name, "post")
        XCTAssertEqual(postBuildPhase?.shellPath, "/bin/sh")
        XCTAssertEqual(postBuildPhase?.shellScript, "\"$SRCROOT\"/script.sh arg")
    }

    // MARK: - Helpers

    private func createNativeTarget(for target: Target) -> PBXNativeTarget {
        let nativeTarget = PBXNativeTarget(name: target.name)
        pbxproj.add(object: nativeTarget)
        return nativeTarget
    }

    private func createPbxProject(pbxproj: PBXProj) -> PBXProject {
        let configList = XCConfigurationList(buildConfigurations: [])
        pbxproj.add(object: configList)
        let mainGroup = PBXGroup()
        pbxproj.add(object: mainGroup)
        let pbxProject = PBXProject(
            name: "Project",
            buildConfigurationList: configList,
            compatibilityVersion: "0",
            mainGroup: mainGroup
        )
        pbxproj.add(object: pbxProject)
        return pbxProject
    }
}
