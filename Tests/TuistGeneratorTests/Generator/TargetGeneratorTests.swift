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

        path = AbsolutePath("/test")
        pbxproj = PBXProj()
        pbxProject = createPbxProject(pbxproj: pbxproj)
        fileElements = ProjectFileElements([:])

        subject = TargetGenerator()
    }

    override func tearDown() {
        super.tearDown()

        subject = nil
        fileElements = nil
        pbxProject = nil
        pbxproj = nil
        path = nil
    }

    func test_generateTarget_productName() throws {
        // Given
        let target = Target.test(
            name: "MyFramework",
            product: .framework,
            actions: [
                TargetAction(
                    name: "pre",
                    order: .pre,
                    script: .tool("echo", ["pre1", "pre2"])
                ),
                TargetAction(
                    name: "post",
                    order: .post,
                    script: .tool("echo", ["post1", "post2"]),
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
        let graph = ValueGraph.test()
        let graphTraverser = ValueGraphTraverser(graph: graph)
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

        guard
            let preBuildPhase = generatedTarget.buildPhases.first(where: { $0.name() == "pre" }),
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
        let targetA = Target.test(name: "TargetA")
        let targetB = Target.test(name: "TargetB")
        let nativeTargetA = createNativeTarget(for: targetA)
        let nativeTargetB = createNativeTarget(for: targetB)
        let graph = ValueGraph.test(
            projects: [path: .test(path: path)],
            targets: [
                path: [
                    targetA.name: targetA,
                    targetB.name: targetB,
                ],
            ],
            dependencies: [
                .target(name: targetA.name, path: path): [
                    .target(name: targetB.name, path: path),
                ],
            ]
        )
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        try subject.generateTargetDependencies(
            path: path,
            targets: [targetA, targetB],
            nativeTargets: [
                "TargetA": nativeTargetA,
                "TargetB": nativeTargetB,
            ],
            graphTraverser: graphTraverser
        )

        // Then
        XCTAssertEqual(nativeTargetA.dependencies.map(\.name), [
            "TargetB",
        ])
    }

    func test_generateTarget_actions() throws {
        // Given
        let graph = ValueGraph.test()
        let graphTraverser = ValueGraphTraverser(graph: graph)
        let target = Target.test(
            sources: [],
            resources: [],
            actions: [
                TargetAction(
                    name: "post",
                    order: .post,
                    script: .scriptPath(path.appending(component: "script.sh"), args: ["arg"])
                ),
                TargetAction(
                    name: "pre",
                    order: .pre,
                    script: .scriptPath(path.appending(component: "script.sh"), args: ["arg"])
                ),
            ]
        )
        let project = Project.test(path: path, sourceRootPath: path, xcodeProjPath: path.appending(component: "Project.xcodeproj"), targets: [target])
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
