import Foundation
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

    @Test func sourceFilesRemainBuildableWithoutDuplicatingNavigatorGroups() throws {
        let root: AbsolutePath = "/Package/Sources/CLib"
        let source = root.appending(component: "CLib.c")
        let target = Target.test(name: "CLib", sources: [.init(path: source)], headers: .test(sourceLayout: .init(
            root: root, publicHeaders: root.appending(component: "include"),
            moduleMap: root.appending(components: "include", "module.modulemap"),
            moduleName: "CLib", usesDirectoryModuleMap: false
        )))
        let project = Project.test(
            path: "/Package",
            sourceRootPath: "/Package",
            xcodeProjPath: "/Derived/CLib/CLib.xcodeproj",
            targets: [target]
        )
        let files = ProjectFileElements()
        let pbx = PBXProj()
        let groups = ProjectGroups.generate(project: project, pbxproj: pbx)
        try files.generate(
            files: Array(files.targetFiles(target: target, project: project)),
            groups: groups,
            pbxproj: pbx,
            sourceRootPath: project.sourceRootPath
        )
        let reference = try #require(files.elements[source] as? PBXFileReference)
        #expect(reference.sourceTree == .sourceRoot)
        #expect(reference.path == "../../Package/Sources/CLib/CLib.c")
        #expect(!pbx.groups.contains { $0.children.contains(reference) })
        #expect(!pbx.groups.contains { $0.path == "CLib" })
        #expect(files.folderReferences[root] != nil)
    }

    @Test func compileOnlyReferencesHaveStableIDs() throws {
        func generate() throws -> Data {
            let main = PBXGroup(children: [])
            let configurations = XCConfigurationList()
            let project = PBXProject(
                name: "CLib", buildConfigurationList: configurations,
                compatibilityVersion: nil, preferredProjectObjectVersion: nil,
                minimizedProjectReferenceProxies: nil, mainGroup: main
            )
            let pbx = PBXProj(rootObject: project, objects: [main, configurations, project])
            let reference = PBXFileReference(sourceTree: .sourceRoot, path: "../../Sources/CLib.c")
            pbx.add(object: reference)
            let path: AbsolutePath = "/Sources/CLib.c"
            let files = ProjectFileElements([path: reference])
            try files.finalizeBuildFileReferences(in: pbx, mainGroup: main)
            #expect(!reference.uuid.hasPrefix("TEMP_"))
            #expect(main.children.isEmpty)
            return try #require(try pbx.dataRepresentation(outputSettings: PBXOutputSettings()))
        }
        #expect(try generate() == generate())
    }

    @Test func packageModuleMapsAreBoundAfterBinaryReplacement() throws {
        let root: AbsolutePath = "/Package"
        let include = root.appending(component: "include")
        let moduleMap = include.appending(component: "module.modulemap")
        let package = Target.test(name: "CLib", settings: .test(base: [
            "MODULEMAP_FILE": .string(moduleMap.pathString),
            "HEADER_SEARCH_PATHS": .array([include.pathString]),
        ]), headers: .test(sourceLayout: .init(
            root: root, publicHeaders: include, moduleMap: moduleMap, moduleName: "CLib", usesDirectoryModuleMap: false
        )))
        let consumer = Target.test(name: "Consumer", settings: .test(
            baseDebug: ["OTHER_SWIFT_FLAGS": ["-D", "BASE_DEBUG"]],
            configurations: [
                .debug: .init(settings: ["OTHER_CFLAGS": "-DDEBUG"]),
                .release: .init(settings: ["OTHER_CFLAGS": ["$(inherited)", "-DRELEASE"]]),
            ]
        ))
        let origin = GraphDependency.target(name: "Consumer", path: root)
        let dependency = GraphDependency.target(name: "CLib", path: root)
        let graph = Graph.test(
            path: root,
            projects: [root: .test(
                path: root, xcodeProjPath: root.appending(components: "Derived", "Package.xcodeproj"), targets: [
                    package,
                    consumer,
                ]
            )],
            dependencies: [origin: [dependency]]
        )
        let (prepared, effects, _) = try ModuleMapMapper().map(graph: graph, environment: MapperEnvironment())
        #expect(prepared.projects[root]?.targets["Consumer"]?.settings?.base["OTHER_CFLAGS"] == nil)
        #expect(!effects.contains { if case .file = $0 { return true }; return false })
        let (source, _, _) = try SwiftPackageSourceHeadersMapper().map(graph: prepared, environment: MapperEnvironment())
        #expect(source.projects[root]?.targets["Consumer"]?.settings?.base["OTHER_CFLAGS"] == .array([
            "$(inherited)", "-fmodule-map-file=\"$(PROJECT_DIR)/../include/module.modulemap\"",
        ]))
        let settings = try #require(source.projects[root]?.targets["Consumer"]?.settings)
        #expect(settings.baseDebug["OTHER_SWIFT_FLAGS"] == .array([
            "-D", "BASE_DEBUG", "-Xcc", "-fmodule-map-file=\"$(PROJECT_DIR)/../include/module.modulemap\"",
        ]))
        #expect(settings.configurations[.debug]??.settings["OTHER_CFLAGS"] == .array([
            "-DDEBUG", "-fmodule-map-file=\"$(PROJECT_DIR)/../include/module.modulemap\"",
        ]))
        #expect(settings.configurations[.release]??.settings["OTHER_CFLAGS"] == .array(["$(inherited)", "-DRELEASE"]))
        var cached = prepared
        cached.projects[root]?.targets["CLib"] = nil
        cached.dependencies[origin] = [.testXCFramework(path: root.appending(component: "CLib.xcframework"))]
        let (binary, _, _) = try SwiftPackageSourceHeadersMapper().map(graph: cached, environment: MapperEnvironment())
        #expect(binary.projects[root]?.targets["Consumer"]?.settings?.base["OTHER_CFLAGS"] == nil)
        #expect(binary.projects[root]?.targets["Consumer"]?.settings?.base["HEADER_SEARCH_PATHS"] == nil)
    }
}
