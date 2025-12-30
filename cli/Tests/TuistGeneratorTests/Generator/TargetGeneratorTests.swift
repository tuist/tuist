import Foundation
import Path
import Testing
import TuistCore
import XcodeGraph
import XcodeProj
@testable import TuistGenerator

struct TargetGeneratorTests {
    var path: AbsolutePath!
    var subject: TargetGenerator!
    var pbxproj: PBXProj!
    var pbxProject: PBXProject!
    var fileElements: ProjectFileElements!

    init() {
        path = try! AbsolutePath(validating: "/test")
        pbxproj = PBXProj()
        pbxProject = createPbxProject(pbxproj: pbxproj)
        fileElements = ProjectFileElements([:])
        subject = TargetGenerator()
    }

    @Test func generateTarget_synchronizedGroups() async throws {
        // Given
        let buildableFolderPath = path.appending(component: "Sources")
        let target = Target.test(
            name: "MyFramework",
            product: .framework,
            scripts: [],
            buildableFolders: [
                BuildableFolder(path: buildableFolderPath, exceptions: BuildableFolderExceptions(exceptions: [
                    BuildableFolderException(
                        excluded: [path.appending(components: ["Sources", "Excluded.swift"])],
                        compilerFlags: [path.appending(components: ["Sources", "CompilerFlags.swift"]): "-print-stats"],
                        publicHeaders: [path.appending(components: ["Sources", "Headers", "Public.h"])],
                        privateHeaders: [path.appending(components: ["Sources", "Headers", "Private.h"])]
                    ),
                ]), resolvedFiles: [
                    BuildableFolderFile(path: path.appending(components: ["Sources", "Included.swift"]), compilerFlags: nil),
                    BuildableFolderFile(
                        path: path.appending(components: ["Sources", "CompilerFlags.swift"]),
                        compilerFlags: "-print-stats"
                    ),
                    BuildableFolderFile(path: path.appending(components: ["Sources", "Headers", "Public.h"]), compilerFlags: nil),
                    BuildableFolderFile(
                        path: path.appending(components: ["Sources", "Headers", "Private.h"]),
                        compilerFlags: nil
                    ),
                ]),
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
        let generatedTarget = try await subject.generateTarget(
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
        #expect(generatedTarget.fileSystemSynchronizedGroups?.count != 0)
        let group = try #require(generatedTarget.fileSystemSynchronizedGroups?.first)
        #expect(group.path == "Sources")
        #expect(group.exceptions?.count == 1)
        let exception = try #require(group.exceptions?.first as? PBXFileSystemSynchronizedBuildFileExceptionSet)
        #expect(exception.membershipExceptions == ["Excluded.swift"])
        #expect(exception.additionalCompilerFlagsByRelativePath == ["CompilerFlags.swift": "-print-stats"])
        #expect(exception.publicHeaders == ["Headers/Public.h"])
        #expect(exception.privateHeaders == ["Headers/Private.h"])
    }

    @Test func generateTarget_productName() async throws {
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
        let generatedTarget = try await subject.generateTarget(
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
        #expect(generatedTarget.productName == "MyFramework")
        #expect(generatedTarget.productNameWithExtension() == "MyFramework.framework")
        #expect(generatedTarget.productType == .framework)
        let preBuildPhase = try #require(generatedTarget.buildPhases.first(where: { $0.name() == "pre" }))
        let postBuildPhase = try #require(generatedTarget.buildPhases.first(where: { $0.name() == "post" }))

        #expect(preBuildPhase.inputFileListPaths == [])
        #expect(preBuildPhase.outputFileListPaths == [])

        #expect(postBuildPhase.inputFileListPaths == ["/tmp/b"])
        #expect(postBuildPhase.outputFileListPaths == ["/tmp/d"])
    }

    @Test func test_generateTargetDependencies() async throws {
        // Given
        let targetA = Target.test(
            name: "TargetA",
            destinations: [.mac, .iPhone]
        )
        let targetB = Target.test(
            name: "TargetB",
            destinations: [.mac, .iPhone]
        )
        let targetC = Target.test(name: "TargetC")
        let project: Project = .test(path: path, targets: [targetA, targetB, targetC])
        let nativeTargetA = createNativeTarget(for: targetA)
        let nativeTargetB = createNativeTarget(for: targetB)
        let nativeTargetC = createNativeTarget(for: targetC)
        let graph = Graph.test(
            projects: [path: project],
            dependencies: [
                .target(name: targetA.name, path: path): [
                    .target(name: targetB.name, path: path),
                    .target(name: targetC.name, path: path),
                ],
            ],
            dependencyConditions: [
                GraphEdge(
                    from: .target(name: targetA.name, path: path),
                    to: .target(name: targetC.name, path: path)
                ):
                    .when([.ios])!,
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
            #expect(dependency.name == expected[index].name)
            #expect(dependency.platformFilter == expected[index].platformFilter)
            #expect(dependency.platformFilters == expected[index].platformFilters)
        }
    }

    @Test func generateTarget_actions() async throws {
        // Given
        let graph = Graph.test()
        let graphTraverser = GraphTraverser(graph: graph)
        let target = Target.test(
            sources: [],
            resources: .init([]),
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
        let pbxTarget = try await subject.generateTarget(
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
        #expect(preBuildPhase?.name == "pre")
        #expect(preBuildPhase?.shellPath == "/bin/sh")
        #expect(preBuildPhase?.shellScript == "\"$SRCROOT\"/script.sh arg")

        let postBuildPhase = pbxTarget.buildPhases.last as? PBXShellScriptBuildPhase
        #expect(postBuildPhase?.name == "post")
        #expect(postBuildPhase?.shellPath == "/bin/sh")
        #expect(postBuildPhase?.shellScript == "\"$SRCROOT\"/script.sh arg")
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
            preferredProjectObjectVersion: nil,
            minimizedProjectReferenceProxies: nil,
            mainGroup: mainGroup
        )
        pbxproj.add(object: pbxProject)
        return pbxProject
    }
}
