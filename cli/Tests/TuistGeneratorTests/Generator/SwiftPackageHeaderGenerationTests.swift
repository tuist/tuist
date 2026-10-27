import Path
import Testing
import TuistCore
import XcodeGraph
import XcodeProj
@testable import TuistGenerator

struct SwiftPackageHeaderGenerationTests {
    @Test(arguments: [1, 10000]) func headerCountDoesNotIncreaseBuildGraph(count: Int) throws {
        let root: AbsolutePath = "/Package"
        let headers = Headers(
            public: (0 ..< count).map { root.appending(components: "include", "vendor", "Header\($0).hpp") },
            private: [], project: [],
            sourceLayout: .init(
                root: root, publicHeaders: root.appending(component: "include"),
                moduleMap: root.appending(components: "include", "module.modulemap"),
                moduleName: "CLib", usesDirectoryModuleMap: false
            )
        )
        let target = Target.test(name: "CLib", headers: headers)
        let project = Project.test(path: root, targets: [target])
        let files = ProjectFileElements()
        let elements = try files.targetFiles(target: target, project: project)
        #expect(elements.contains(.folder(path: root, group: target.filesGroup)))
        #expect(!elements.contains { headers.public.contains($0.path) })
        let pbx = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "CLib")
        try BuildPhaseGenerator().generateHeadersBuildPhase(
            headers: headers, buildableFolders: [], pbxTarget: nativeTarget,
            fileElements: files, pbxproj: pbx
        )
        #expect(nativeTarget.buildPhases.isEmpty)
        #expect(pbx.buildFiles.isEmpty)
    }

    @Test func directoryNamespacesDoNotChangeCustomModuleMaps() throws {
        let root: AbsolutePath = "/Package"
        func target(_ name: String, directory: Bool) -> Target {
            .test(name: name, headers: .test(
                public: [
                    root.appending(components: "include", name, "Nested.h"),
                    root.appending(components: "include", "Flat.h"),
                ],
                sourceLayout: .init(
                    root: root, publicHeaders: root.appending(component: "include"),
                    moduleMap: root.appending(component: "module.modulemap"),
                    moduleName: name, usesDirectoryModuleMap: directory
                )
            ))
        }
        let project = Project.test(
            path: root,
            targets: [target("Directory", directory: true), target("Custom", directory: false)]
        )
        let graph = Graph.test(projects: [root: project])
        let (mapped, effects) = SwiftPackageHeaderNamespaceMapper().map(graph: graph)
        #expect(effects.count == 1)
        #expect(mapped.projects[root]?.targets["Directory"]?.settings?.base["HEADER_SEARCH_PATHS"] != nil)
        #expect(mapped.projects[root]?.targets["Custom"]?.settings == project.targets["Custom"]?.settings)
    }
}
