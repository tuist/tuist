import TuistCore
import TuistCoreTesting
@testable import TuistGenerator

final class ConfigShowEnvironmentTests: TuistUnitTestCase {
    func test_generateTarget_actions() throws {
        // Given
        let graph = Graph.test()
        let target = Target.test(sources: [],
                                 resources: [],
                                 actions: [
                                     TargetAction(name: "post", order: .post, path: path.appending(component: "script.sh"), arguments: ["arg"], showEnvVarsInLog: false),
                                     TargetAction(name: "pre", order: .pre, path: path.appending(component: "script.sh"), arguments: ["arg"]),
                                 ])
        let project = Project.test(path: path, sourceRootPath: path, xcodeProjPath: path.appending(component: "Project.xcodeproj"), targets: [target])
        let groups = ProjectGroups.generate(project: project,
                                            pbxproj: pbxproj,
                                            playgrounds: MockPlaygrounds())
        try fileElements.generateProjectFiles(project: project,
                                              graph: graph,
                                              groups: groups,
                                              pbxproj: pbxproj)

        // When
        let pbxTarget = try subject.generateTarget(target: target,
                                                   project: project,
                                                   pbxproj: pbxproj,
                                                   pbxProject: pbxProject,
                                                   projectSettings: Settings.test(),
                                                   fileElements: fileElements,
                                                   path: path,
                                                   graph: graph)

        // Then
        let preBuildPhase = try XCTUnwrap(pbxTarget.buildPhases.first as? PBXShellScriptBuildPhase)
        XCTAssertEqual(preBuildPhase.name, "pre")
        XCTAssertEqual(preBuildPhase.shellPath, "/bin/sh")
        XCTAssertEqual(preBuildPhase.shellScript, "\"${PROJECT_DIR}\"/script.sh arg")
        XCTAssertTrue(preBuildPhase.showEnvVarsInLog)

        let postBuildPhase = try XCTUnwrap(pbxTarget.buildPhases.last as? PBXShellScriptBuildPhase)
        XCTAssertEqual(postBuildPhase.name, "post")
        XCTAssertEqual(postBuildPhase.shellPath, "/bin/sh")
        XCTAssertEqual(postBuildPhase.shellScript, "\"${PROJECT_DIR}\"/script.sh arg")
        XCTAssertFalse(postBuildPhase.showEnvVarsInLog)
    }
}
