import Basic
import Foundation
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
        fileElements = ProjectFileElements([:], playgrounds: MockPlaygrounds())

        subject = TargetGenerator()
    }

    func test_generateTarget_productName() throws {
        // Given
        let target = Target.test(name: "MyFramework",
                                 product: .framework,
                                 actions: [
                                     TargetAction(name: "pre",
                                                  order: .pre,
                                                  tool: "echo",
                                                  arguments: ["pre1", "pre2"]),
                                     TargetAction(name: "post",
                                                  order: .post,
                                                  tool: "echo",
                                                  path: "/tmp",
                                                  arguments: ["post1", "post2"],
                                                  inputFileListPaths: ["/tmp/b"],
                                                  outputFileListPaths: ["/tmp/d"]),
                                 ])
        let project = Project.test(path: path, targets: [target])
        let graph = Graph.test()
        let groups = ProjectGroups.generate(project: project,
                                            pbxproj: pbxproj,
                                            sourceRootPath: path,
                                            playgrounds: MockPlaygrounds())
        try fileElements.generateProjectFiles(project: project,
                                              graph: graph,
                                              groups: groups,
                                              pbxproj: pbxproj,
                                              sourceRootPath: path)

        // When
        let generatedTarget = try subject.generateTarget(target: target,
                                                         pbxproj: pbxproj,
                                                         pbxProject: pbxProject,
                                                         projectSettings: Settings.test(),
                                                         fileElements: fileElements,
                                                         path: path,
                                                         sourceRootPath: path,
                                                         graph: graph)

        // Then
        XCTAssertEqual(generatedTarget.productName, "MyFramework")
        XCTAssertEqual(generatedTarget.productNameWithExtension(), "MyFramework.framework")
        XCTAssertEqual(generatedTarget.productType, .framework)

        guard
            let preBuildPhase = generatedTarget.buildPhases.first(where: { $0.name() == "pre" }),
            let postBuildPhase = generatedTarget.buildPhases.first(where: { $0.name() == "post" }) else {
            XCTFail("Failed to generate target with build phases pre and post")
            return
        }

        XCTAssertEqual(preBuildPhase.inputFileListPaths, [])
        XCTAssertEqual(preBuildPhase.outputFileListPaths, [])

        XCTAssertEqual(postBuildPhase.inputFileListPaths, ["/tmp/b"])
        XCTAssertEqual(postBuildPhase.outputFileListPaths, ["/tmp/d"])
    }

    func test_generateTargetDependencies() throws {
        // Given
        let targetA = Target.test(name: "TargetA")
        let targetB = Target.test(name: "TargetB")
        let nativeTargetA = createNativeTarget(for: targetA)
        let nativeTargetB = createNativeTarget(for: targetB)
        let graph = createGraph(project: .test(path: path),
                                dependencies: [
                                    (target: targetA, dependencies: [targetB]),
                                    (target: targetB, dependencies: []),
                                ])

        // When
        try subject.generateTargetDependencies(path: path,
                                               targets: [targetA, targetB],
                                               nativeTargets: [
                                                   "TargetA": nativeTargetA,
                                                   "TargetB": nativeTargetB,
                                               ],
                                               graph: graph)

        // Then
        XCTAssertEqual(nativeTargetA.dependencies.map(\.name), [
            "TargetB",
        ])
    }

    func test_generateTarget_actions() throws {
        // Given
        let graph = Graph.test()
        let target = Target.test(sources: [],
                                 resources: [],
                                 actions: [
                                     TargetAction(name: "post", order: .post, path: path.appending(component: "script.sh"), arguments: ["arg"]),
                                     TargetAction(name: "pre", order: .pre, path: path.appending(component: "script.sh"), arguments: ["arg"]),
                                 ])
        let project = Project.test(path: path, targets: [target])
        let groups = ProjectGroups.generate(project: project,
                                            pbxproj: pbxproj,
                                            sourceRootPath: path,
                                            playgrounds: MockPlaygrounds())
        try fileElements.generateProjectFiles(project: project,
                                              graph: graph,
                                              groups: groups,
                                              pbxproj: pbxproj,
                                              sourceRootPath: path)

        // When
        let pbxTarget = try subject.generateTarget(target: target,
                                                   pbxproj: pbxproj,
                                                   pbxProject: pbxProject,
                                                   projectSettings: Settings.test(),
                                                   fileElements: fileElements,
                                                   path: path,
                                                   sourceRootPath: path,
                                                   graph: graph)

        // Then
        let preBuildPhase = pbxTarget.buildPhases.first as? PBXShellScriptBuildPhase
        XCTAssertEqual(preBuildPhase?.name, "pre")
        XCTAssertEqual(preBuildPhase?.shellPath, "/bin/sh")
        XCTAssertEqual(preBuildPhase?.shellScript, "script.sh arg")

        let postBuildPhase = pbxTarget.buildPhases.last as? PBXShellScriptBuildPhase
        XCTAssertEqual(postBuildPhase?.name, "post")
        XCTAssertEqual(postBuildPhase?.shellPath, "/bin/sh")
        XCTAssertEqual(postBuildPhase?.shellScript, "script.sh arg")
    }

    // MARK: - Helpers

    private func createTargetNodes(project: Project,
                                   dependencies: [(target: Target, dependencies: [Target])]) -> [TargetNode] {
        let nodesCache = Dictionary(uniqueKeysWithValues: dependencies.map {
            ($0.target.name, TargetNode(project: project,
                                        target: $0.target,
                                        dependencies: []))
        })

        dependencies.forEach {
            let node = nodesCache[$0.target.name]!
            node.dependencies = $0.dependencies.map { nodesCache[$0.name]! }
        }

        return dependencies.map { nodesCache[$0.target.name]! }
    }

    private func createGraph(project: Project,
                             dependencies: [(target: Target, dependencies: [Target])]) -> Graph {
        let targetNodes = createTargetNodes(project: project, dependencies: dependencies)

        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)

        targetNodes.forEach { cache.add(targetNode: $0) }

        return graph
    }

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
        let pbxProject = PBXProject(name: "Project",
                                    buildConfigurationList: configList,
                                    compatibilityVersion: "0",
                                    mainGroup: mainGroup)
        pbxproj.add(object: pbxProject)
        return pbxProject
    }
}
