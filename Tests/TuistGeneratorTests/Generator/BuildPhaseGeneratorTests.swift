import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class BuildPhaseGenerationErrorTests: TuistUnitTestCase {
    func test_description_when_missingFileReference() {
        let path = AbsolutePath("/test")
        let expected = "Trying to add a file at path \(path.pathString) to a build phase that hasn't been added to the project."
        XCTAssertEqual(BuildPhaseGenerationError.missingFileReference(path).description, expected)
    }

    func test_type_when_missingFileReference() {
        let path = AbsolutePath("/test")
        XCTAssertEqual(BuildPhaseGenerationError.missingFileReference(path).type, .bug)
    }
}

final class BuildPhaseGeneratorTests: TuistUnitTestCase {
    var subject: BuildPhaseGenerator!
    var errorHandler: MockErrorHandler!

    override func setUp() {
        subject = BuildPhaseGenerator()
        errorHandler = MockErrorHandler()
        super.setUp()
    }

    override func tearDown() {
        subject = nil
        errorHandler = nil
        super.tearDown()
    }

    func test_generateSourcesBuildPhase() throws {
        // Given
        let target = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: target)

        let sources: [SourceFile] = [
            SourceFile(path: "/test/file1.swift", compilerFlags: "flag"),
            SourceFile(path: "/test/file2.swift"),
        ]

        let fileElements = createFileElements(for: sources.map(\.path))

        // When
        try subject.generateSourcesBuildPhase(
            files: sources,
            coreDataModels: [],
            pbxTarget: target,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let buildPhase = try target.sourcesBuildPhase()
        let buildFiles = buildPhase?.files ?? []
        let buildFilesNames = buildFiles.map {
            $0.file?.name
        }

        XCTAssertEqual(buildFilesNames, [
            "file1.swift",
            "file2.swift",
        ])

        let buildFilesSettings = buildFiles.map {
            $0.settings as? [String: String]
        }

        XCTAssertEqual(buildFilesSettings, [
            ["COMPILER_FLAGS": "flag"],
            nil,
        ])
    }

    func test_generateScripts() throws {
        // Given
        let target = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: target)
        let targetScript = TargetScript(name: "Test", script: "Script", showEnvVarsInLog: true, hashable: false)
        let targetScripts = [targetScript]

        // When
        subject.generateScripts(
            targetScripts,
            pbxTarget: target,
            pbxproj: pbxproj
        )

        // Then
        let buildPhase = try XCTUnwrap(target.buildPhases.first as? PBXShellScriptBuildPhase)
        XCTAssertEqual(buildPhase.name, targetScript.name)
        XCTAssertEqual(buildPhase.shellScript, targetScript.script)
        XCTAssertEqual(buildPhase.shellPath, "/bin/sh")
        XCTAssertEqual(buildPhase.files, [])
        XCTAssertTrue(buildPhase.showEnvVarsInLog)
    }

    func test_generateSourcesBuildPhase_throws_when_theFileReferenceIsMissing() {
        let path = AbsolutePath("/test/file.swift")
        let target = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: target)
        let fileElements = ProjectFileElements()

        XCTAssertThrowsError(try subject.generateSourcesBuildPhase(
            files: [SourceFile(path: path, compilerFlags: nil)],
            coreDataModels: [],
            pbxTarget: target,
            fileElements: fileElements,
            pbxproj: pbxproj
        )) {
            XCTAssertEqual($0 as? BuildPhaseGenerationError, BuildPhaseGenerationError.missingFileReference(path))
        }
    }

    func test_generateSourcesBuildPhase_whenLocalizedFile() throws {
        // Given
        let target = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: target)

        let sources: [SourceFile] = [
            SourceFile(path: "/path/sources/Base.lproj/OTTSiriExtension.intentdefinition", compilerFlags: nil),
            SourceFile(path: "/path/sources/en.lproj/OTTSiriExtension.intentdefinition", compilerFlags: nil),
        ]

        let fileElements = createLocalizedResourceFileElements(for: [
            "/path/sources/OTTSiriExtension.intentdefinition",
        ])

        // When
        try subject.generateSourcesBuildPhase(
            files: sources,
            coreDataModels: [],
            pbxTarget: target,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let buildPhase = try target.sourcesBuildPhase()
        let buildFiles = buildPhase?.files ?? []

        XCTAssertEqual(buildFiles.map(\.file), [
            fileElements.elements["/path/sources/OTTSiriExtension.intentdefinition"],
        ])
    }

    func test_generateSourcesBuildPhase_throws_whenLocalizedFileAndFileReferenceIsMissing() {
        let path = AbsolutePath("/test/Base.lproj/file.intentdefinition")
        let target = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: target)
        let fileElements = ProjectFileElements()

        XCTAssertThrowsError(try subject.generateSourcesBuildPhase(
            files: [SourceFile(path: path, compilerFlags: nil)],
            coreDataModels: [],
            pbxTarget: target,
            fileElements: fileElements,
            pbxproj: pbxproj
        )) {
            XCTAssertEqual($0 as? BuildPhaseGenerationError, BuildPhaseGenerationError.missingFileReference(path))
        }
    }

    func test_generateHeadersBuildPhase() throws {
        // Given
        let target = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: target)

        let headers = Headers(
            public: ["/test/Public1.h"],
            private: ["/test/Private1.h"],
            project: ["/test/Project1.h"]
        )

        let fileElements = createFileElements(for: headers)

        // When
        try subject.generateHeadersBuildPhase(
            headers: headers,
            pbxTarget: target,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let buildPhase = try XCTUnwrap(target.buildPhases.first as? PBXHeadersBuildPhase)
        let buildFiles = buildPhase.files ?? []

        struct FileWithSettings: Equatable {
            var name: String?
            var attributes: [String]?
        }

        let buildFilesWithSettings = buildFiles.map {
            FileWithSettings(
                name: $0.file?.name,
                attributes: $0.settings?["ATTRIBUTES"] as? [String]
            )
        }

        XCTAssertEqual(buildFilesWithSettings, [
            FileWithSettings(name: "Private1.h", attributes: ["Private"]),
            FileWithSettings(name: "Public1.h", attributes: ["Public"]),
            FileWithSettings(name: "Project1.h", attributes: nil),
        ])
    }

    func test_generateHeadersBuildPhase_empty_when_iOSAppTarget() throws {
        let tmpDir = try temporaryPath()
        let pbxTarget = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: pbxTarget)

        let fileElements = ProjectFileElements()
        let path = AbsolutePath("/test/file.swift")

        let sourceFileReference = PBXFileReference(sourceTree: .group, name: "Test")
        fileElements.elements[path] = sourceFileReference

        let headerPath = AbsolutePath("/test.h")
        let headers = Headers.test(public: [path], private: [], project: [])

        let headerFileReference = PBXFileReference()
        fileElements.elements[headerPath] = headerFileReference

        let target = Target.test(
            platform: .iOS,
            sources: [SourceFile(path: "/test/file.swift", compilerFlags: nil)],
            headers: headers
        )

        let graph = ValueGraph.test(path: tmpDir)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        try subject.generateBuildPhases(
            path: tmpDir,
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        XCTAssertEmpty(pbxTarget.buildPhases.filter { $0 is PBXHeadersBuildPhase })
    }

    func test_generateHeadersBuildPhase_before_generateSourceBuildPhase() throws {
        let tmpDir = try temporaryPath()
        let pbxTarget = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: pbxTarget)

        let fileElements = ProjectFileElements()
        let path = AbsolutePath("/test/file.swift")

        let sourceFileReference = PBXFileReference(sourceTree: .group, name: "Test")
        fileElements.elements[path] = sourceFileReference

        let headerPath = AbsolutePath("/test.h")
        let headers = Headers.test(public: [path], private: [], project: [])

        let headerFileReference = PBXFileReference()
        fileElements.elements[headerPath] = headerFileReference

        let target = Target.test(
            platform: .iOS,
            product: .framework,
            sources: [SourceFile(path: "/test/file.swift", compilerFlags: nil)],
            headers: headers
        )
        let graph = ValueGraph.test(path: tmpDir)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        try subject.generateBuildPhases(
            path: tmpDir,
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        let firstBuildPhase: PBXBuildPhase? = pbxTarget.buildPhases.first
        XCTAssertNotNil(firstBuildPhase)
        XCTAssertTrue(firstBuildPhase is PBXHeadersBuildPhase)

        let secondBuildPhase: PBXBuildPhase? = pbxTarget.buildPhases[1]
        XCTAssertTrue(secondBuildPhase is PBXSourcesBuildPhase)
    }

    func test_generateResourcesBuildPhase_whenLocalizedFile() throws {
        // Given
        let path = try temporaryPath()
        let files: [AbsolutePath] = [
            "/path/resources/en.lproj/Main.storyboard",
            "/path/resources/en.lproj/App.strings",
            "/path/resources/fr.lproj/Main.storyboard",
            "/path/resources/fr.lproj/App.strings",
        ]

        let resources = files.map { ResourceFileElement.file(path: $0) }
        let fileElements = createLocalizedResourceFileElements(for: [
            "/path/resources/Main.storyboard",
            "/path/resources/App.strings",
        ])

        let nativeTarget = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        let graph = ValueGraph.test(path: path)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        try subject.generateResourcesBuildPhase(
            path: "/path",
            target: .test(resources: resources),
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let buildPhase = nativeTarget.buildPhases.first
        XCTAssertEqual(buildPhase?.files?.map(\.file), [
            fileElements.elements["/path/resources/Main.storyboard"],
            fileElements.elements["/path/resources/App.strings"],
        ])
    }

    func test_generateSourcesBuildPhase_whenCoreDataModel() throws {
        // Given
        let coreDataModel = CoreDataModel(
            path: AbsolutePath("/Model.xcdatamodeld"),
            versions: [AbsolutePath("/Model.xcdatamodeld/1.xcdatamodel")],
            currentVersion: "1"
        )
        let target = Target.test(resources: [], coreDataModels: [coreDataModel])
        let fileElements = ProjectFileElements()
        let pbxproj = PBXProj()

        let versionGroup = XCVersionGroup()
        pbxproj.add(object: versionGroup)
        fileElements.elements[AbsolutePath("/Model.xcdatamodeld")] = versionGroup

        let model = PBXFileReference()
        pbxproj.add(object: model)
        versionGroup.children.append(model)
        fileElements.elements[AbsolutePath("/Model.xcdatamodeld/1.xcdatamodel")] = model

        let nativeTarget = PBXNativeTarget(name: "Test")

        // When
        try subject.generateSourcesBuildPhase(
            files: target.sources,
            coreDataModels: target.coreDataModels,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let pbxBuildPhase: PBXBuildPhase = try XCTUnwrap(nativeTarget.buildPhases.first as? PBXSourcesBuildPhase)
        let pbxBuildFile: PBXBuildFile = try XCTUnwrap(pbxBuildPhase.files?.first)
        XCTAssertEqual(pbxBuildFile.file, versionGroup)
        XCTAssertEqual(versionGroup.currentVersion, model)
    }

    func test_generateResourcesBuildPhase_whenNormalResource() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let path = AbsolutePath("/image.png")
        let target = Target.test(resources: [.file(path: path)])
        let fileElements = ProjectFileElements()
        let pbxproj = PBXProj()
        let fileElement = PBXFileReference()
        pbxproj.add(object: fileElement)
        fileElements.elements[path] = fileElement

        let nativeTarget = PBXNativeTarget(name: "Test")

        let graph = ValueGraph.test(path: temporaryPath)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        try subject.generateResourcesBuildPhase(
            path: "/path",
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let pbxBuildPhase: PBXBuildPhase? = nativeTarget.buildPhases.first
        XCTAssertNotNil(pbxBuildPhase)
        XCTAssertTrue(pbxBuildPhase is PBXResourcesBuildPhase)
        let pbxBuildFile: PBXBuildFile? = pbxBuildPhase?.files?.first
        XCTAssertEqual(pbxBuildFile?.file, fileElement)
    }

    func test_generateResourcesBuildPhase_whenContainsResourcesTags() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let resources: [ResourceFileElement] = [.file(path: "/file.type", tags: ["fileTag"]),
                                                .folderReference(path: "/folder", tags: ["folderTag"])]
        let target = Target.test(resources: resources)
        let fileElements = ProjectFileElements()
        let pbxproj = PBXProj()

        let fileElement = PBXFileReference()
        let folderElement = PBXFileReference()
        pbxproj.add(object: fileElement)
        pbxproj.add(object: folderElement)
        fileElements.elements["/file.type"] = fileElement
        fileElements.elements["/folder"] = folderElement

        let nativeTarget = PBXNativeTarget(name: "Test")

        let graph = ValueGraph.test(path: temporaryPath)
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        try subject.generateResourcesBuildPhase(
            path: "/path",
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let pbxBuildPhase: PBXBuildPhase? = nativeTarget.buildPhases.first
        XCTAssertNotNil(pbxBuildPhase)
        XCTAssertTrue(pbxBuildPhase is PBXResourcesBuildPhase)

        let resourceBuildPhase = try XCTUnwrap(nativeTarget.buildPhases.first as? PBXResourcesBuildPhase)
        let allFileSettings = resourceBuildPhase.files?.map { $0.settings as? [String: AnyHashable] }
        XCTAssertEqual(allFileSettings, [
            ["ASSET_TAGS": ["fileTag"]],
            ["ASSET_TAGS": ["folderTag"]],
        ])
    }

    func test_generateResourceBundle() throws {
        // Given
        let path = AbsolutePath("/path")
        let bundle1 = Target.test(name: "Bundle1", product: .bundle)
        let bundle2 = Target.test(name: "Bundle2", product: .bundle)
        let app = Target.test(name: "App", product: .app)

        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createProductFileElements(for: [bundle1, bundle2])

        let project = Project.test(path: path)
        let targets: [AbsolutePath: [String: Target]] = [project.path: [
            bundle1.name: bundle1,
            bundle2.name: bundle2,
            app.name: app,
        ]]
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: bundle1.name, path: project.path): Set(),
            .target(name: bundle2.name, path: project.path): Set(),
            .target(name: app.name, path: project.path): Set([.target(name: bundle1.name, path: project.path),
                                                              .target(name: bundle2.name, path: project.path)]),
        ]
        let graph = ValueGraph.test(
            path: path,
            projects: [project.path: project],
            targets: targets,
            dependencies: dependencies
        )
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        try subject.generateResourcesBuildPhase(
            path: path,
            target: app,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let resourcePhase = try nativeTarget.resourcesBuildPhase()
        XCTAssertEqual(resourcePhase?.files?.compactMap { $0.file?.nameOrPath }, [
            "Bundle1",
            "Bundle2",
        ])
    }

    func test_generateResourceBundle_fromProjectDependency() throws {
        // Given
        let path = try temporaryPath()
        let bundle = Target.test(name: "Bundle1", product: .bundle)
        let projectA = Project.test(path: "/path/a")

        let app = Target.test(name: "App", product: .app)
        let projectB = Project.test(path: "/path/b")

        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createProductFileElements(for: [bundle])

        let targets: [AbsolutePath: [String: Target]] = [
            projectA.path: [bundle.name: bundle],
            projectB.path: [app.name: app],
        ]
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: bundle.name, path: projectA.path): Set(),
            .target(name: app.name, path: projectB.path): Set([.target(name: bundle.name, path: projectA.path)]),
        ]
        let graph = ValueGraph.test(
            path: path,
            projects: [projectA.path: projectA, projectB.path: projectB],
            targets: targets,
            dependencies: dependencies
        )
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        try subject.generateResourcesBuildPhase(
            path: projectB.path,
            target: app,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let resourcePhase = try nativeTarget.resourcesBuildPhase()
        XCTAssertEqual(resourcePhase?.files?.compactMap { $0.file?.nameOrPath }, [
            "Bundle1",
        ])
    }

    func test_generateCopyFilesBuildPhases() throws {
        // Given
        let fonts: [FileElement] = [
            .file(path: "/path/fonts/font1.ttf"),
            .file(path: "/path/fonts/font2.ttf"),
            .file(path: "/path/fonts/font3.ttf"),
        ]

        let templates: [FileElement] = [
            .file(path: "/path/sharedSupport/tuist.rtfd"),
        ]

        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createFileElements(for: (fonts + templates).map(\.path))

        let target = Target.test(copyFiles: [
            CopyFilesAction(name: "Copy Fonts", destination: .resources, subpath: "Fonts", files: fonts),
            CopyFilesAction(name: "Copy Templates", destination: .sharedSupport, subpath: "Templates", files: templates),
        ])

        // When
        try subject.generateCopyFilesBuildPhases(
            target: target,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let firstBuildPhase = try XCTUnwrap(nativeTarget.buildPhases.first as? PBXCopyFilesBuildPhase)
        XCTAssertEqual(firstBuildPhase.name, "Copy Fonts")
        XCTAssertEqual(firstBuildPhase.dstSubfolderSpec, .resources)
        XCTAssertEqual(firstBuildPhase.dstPath, "Fonts")
        XCTAssertEqual(firstBuildPhase.files?.compactMap { $0.file?.nameOrPath }, [
            "font1.ttf",
            "font2.ttf",
            "font3.ttf",
        ])

        let secondBuildPhase = try XCTUnwrap(nativeTarget.buildPhases.last as? PBXCopyFilesBuildPhase)
        XCTAssertEqual(secondBuildPhase.name, "Copy Templates")
        XCTAssertEqual(secondBuildPhase.dstSubfolderSpec, .sharedSupport)
        XCTAssertEqual(secondBuildPhase.dstPath, "Templates")
        XCTAssertEqual(secondBuildPhase.files?.compactMap { $0.file?.nameOrPath }, ["tuist.rtfd"])
    }

    func test_generateAppExtensionsBuildPhase() throws {
        // Given
        let path = try temporaryPath()
        let projectA = Project.test(path: "/path/a")
        let appExtension = Target.test(name: "AppExtension", product: .appExtension)
        let stickerPackExtension = Target.test(name: "StickerPackExtension", product: .stickerPackExtension)
        let app = Target.test(name: "App", product: .app)
        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createProductFileElements(for: [appExtension, stickerPackExtension])

        let targets: [AbsolutePath: [String: Target]] = [
            projectA.path: [
                appExtension.name: appExtension,
                stickerPackExtension.name: stickerPackExtension,
                app.name: app,
            ],
        ]
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: appExtension.name, path: projectA.path): Set(),
            .target(name: stickerPackExtension.name, path: projectA.path): Set(),
            .target(name: app.name, path: projectA.path): Set([
                .target(name: appExtension.name, path: projectA.path),
                .target(name: stickerPackExtension.name, path: projectA.path),
            ]),
        ]
        let graph = ValueGraph.test(
            path: path,
            projects: [projectA.path: projectA],
            targets: targets,
            dependencies: dependencies
        )
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        try subject.generateAppExtensionsBuildPhase(
            path: projectA.path,
            target: app,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let pbxBuildPhase: PBXBuildPhase? = nativeTarget.buildPhases.first
        XCTAssertNotNil(pbxBuildPhase)
        XCTAssertTrue(pbxBuildPhase is PBXCopyFilesBuildPhase)
        XCTAssertEqual(pbxBuildPhase?.files?.compactMap { $0.file?.nameOrPath }, [
            "AppExtension",
            "StickerPackExtension",
        ])
        XCTAssertEqual(
            pbxBuildPhase?.files?.compactMap { $0.settings as? [String: [String]] },
            [["ATTRIBUTES": ["RemoveHeadersOnCopy"]],
             ["ATTRIBUTES": ["RemoveHeadersOnCopy"]]]
        )
    }

    func test_generateAppExtensionsBuildPhase_noBuildPhase_when_appDoesntHaveAppExtensions() throws {
        // Given
        let app = Target.test(name: "App", product: .app)
        let project = Project.test()
        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = ProjectFileElements()

        let targets: [AbsolutePath: [String: Target]] = [
            project.path: [app.name: app],
        ]
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: app.name, path: project.path): Set(),
        ]
        let graph = ValueGraph.test(
            path: project.path,
            projects: [project.path: project],
            targets: targets,
            dependencies: dependencies
        )
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        try subject.generateAppExtensionsBuildPhase(
            path: project.path,
            target: app,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        XCTAssertTrue(nativeTarget.buildPhases.isEmpty)
    }

    func test_generateWatchBuildPhase() throws {
        // Given
        let app = Target.test(name: "App", product: .app)
        let watchApp = Target.test(name: "WatchApp", product: .watch2App)
        let project = Project.test()
        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createProductFileElements(for: [app, watchApp])

        let targets: [AbsolutePath: [String: Target]] = [
            project.path: [app.name: app, watchApp.name: watchApp],
        ]
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: watchApp.name, path: project.path): Set(),
            .target(name: app.name, path: project.path): Set([.target(name: watchApp.name, path: project.path)]),
        ]
        let graph = ValueGraph.test(
            path: project.path,
            projects: [project.path: project],
            targets: targets,
            dependencies: dependencies
        )
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        try subject.generateEmbedWatchBuildPhase(
            path: project.path,
            target: app,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )
        // Then
        let pbxBuildPhase = try XCTUnwrap(nativeTarget.buildPhases.first as? PBXCopyFilesBuildPhase)
        XCTAssertEqual(pbxBuildPhase.files?.compactMap { $0.file?.nameOrPath }, [
            "WatchApp",
        ])
        XCTAssertEqual(
            pbxBuildPhase.files?.compactMap { $0.settings as? [String: [String]] },
            [["ATTRIBUTES": ["RemoveHeadersOnCopy"]]]
        )
    }

    func test_generateTarget_actions() throws {
        // Given
        system.swiftVersionStub = { "5.2" }
        let fileElements = ProjectFileElements([:])
        let graph = ValueGraph.test()
        let graphTraverser = ValueGraphTraverser(graph: graph)
        let path = AbsolutePath("/test")
        let pbxproj = PBXProj()
        let pbxProject = createPbxProject(pbxproj: pbxproj)
        let target = Target.test(
            sources: [],
            resources: [],
            actions: [
                TargetAction(
                    name: "post",
                    order: .post,
                    script: .scriptPath(path.appending(component: "script.sh"), args: ["arg"]),
                    showEnvVarsInLog: false,
                    basedOnDependencyAnalysis: false
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
        let pbxTarget = try TargetGenerator().generateTarget(
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
        let preBuildPhase = try XCTUnwrap(pbxTarget.buildPhases.first as? PBXShellScriptBuildPhase)
        XCTAssertEqual(preBuildPhase.name, "pre")
        XCTAssertEqual(preBuildPhase.shellPath, "/bin/sh")
        XCTAssertEqual(preBuildPhase.shellScript, "\"$SRCROOT\"/script.sh arg")
        XCTAssertTrue(preBuildPhase.showEnvVarsInLog)
        XCTAssertFalse(preBuildPhase.alwaysOutOfDate)

        let postBuildPhase = try XCTUnwrap(pbxTarget.buildPhases.last as? PBXShellScriptBuildPhase)
        XCTAssertEqual(postBuildPhase.name, "post")
        XCTAssertEqual(postBuildPhase.shellPath, "/bin/sh")
        XCTAssertEqual(postBuildPhase.shellScript, "\"$SRCROOT\"/script.sh arg")
        XCTAssertFalse(postBuildPhase.showEnvVarsInLog)
        XCTAssertTrue(postBuildPhase.alwaysOutOfDate)
    }

    func test_generateEmbedAppClipsBuildPhase() throws {
        // Given
        let app = Target.test(name: "App", product: .app)
        let appClip = Target.test(name: "AppClip", product: .appClip)
        let project = Project.test()
        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createProductFileElements(for: [app, appClip])

        let targets: [AbsolutePath: [String: Target]] = [
            project.path: [app.name: app, appClip.name: appClip],
        ]
        let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [
            .target(name: appClip.name, path: project.path): Set(),
            .target(name: app.name, path: project.path): Set([.target(name: appClip.name, path: project.path)]),
        ]
        let graph = ValueGraph.test(
            path: project.path,
            projects: [project.path: project],
            targets: targets,
            dependencies: dependencies
        )
        let graphTraverser = ValueGraphTraverser(graph: graph)
        // When
        try subject.generateEmbedAppClipsBuildPhase(
            path: project.path,
            target: app,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let pbxBuildPhase: PBXBuildPhase? = nativeTarget.buildPhases.first
        XCTAssertNotNil(pbxBuildPhase)
        XCTAssertTrue(pbxBuildPhase is PBXCopyFilesBuildPhase)
        XCTAssertEqual(pbxBuildPhase?.files?.compactMap { $0.file?.nameOrPath }, ["AppClip"])
        XCTAssertEqual(
            pbxBuildPhase?.files?.compactMap { $0.settings as? [String: [String]] },
            [["ATTRIBUTES": ["RemoveHeadersOnCopy"]]]
        )
    }

    func test_generateBuildPhases_whenStaticFrameworkWithCoreDataModels() throws {
        // Given
        let path = AbsolutePath("/path/to/project")
        let coreDataModel = CoreDataModel(
            path: path.appending(component: "Model.xcdatamodeld"),
            versions: [
                path.appending(components: "Model.xcdatamodeld", "1.xcdatamodel"),
            ],
            currentVersion: "1"
        )
        let target = Target.test(platform: .iOS, product: .staticFramework, coreDataModels: [coreDataModel])
        let fileElements = createFileElements(for: [coreDataModel])
        let graph = ValueGraph.test(path: path)
        let graphTraverser = ValueGraphTraverser(graph: graph)
        let pbxproj = PBXProj()
        let pbxTarget = PBXNativeTarget(name: target.name)

        // When
        try subject.generateBuildPhases(
            path: "/path/to/target",
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let sourcesBuildPhase = pbxTarget.buildPhases.filter { $0 is PBXSourcesBuildPhase }.first
        let resourcesBuildPhase = pbxTarget.buildPhases.filter { $0 is PBXResourcesBuildPhase }.first
        let sourcesFiles = sourcesBuildPhase?.files?.compactMap {
            $0.file?.nameOrPath
        } ?? []
        let resourcesFiles = resourcesBuildPhase?.files?.compactMap {
            $0.file?.nameOrPath
        } ?? []
        XCTAssertEqual(sourcesFiles, [
            "Model.xcdatamodeld",
        ])
        XCTAssertTrue(resourcesFiles.isEmpty)
    }

    func test_generateBuildPhases_whenBundleWithCoreDataModels() throws {
        // Given
        let path = AbsolutePath("/path/to/project")
        let coreDataModel = CoreDataModel(
            path: path.appending(component: "Model.xcdatamodeld"),
            versions: [
                path.appending(components: "Model.xcdatamodeld", "1.xcdatamodel"),
            ],
            currentVersion: "1"
        )
        let target = Target.test(platform: .iOS, product: .bundle, coreDataModels: [coreDataModel])
        let fileElements = createFileElements(for: [coreDataModel])
        let graph = ValueGraph.test(path: path)
        let graphTraverser = ValueGraphTraverser(graph: graph)
        let pbxproj = PBXProj()
        let pbxTarget = PBXNativeTarget(name: target.name)

        // When
        try subject.generateBuildPhases(
            path: "/path/to/target",
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let sourcesBuildPhase = pbxTarget.buildPhases.filter { $0 is PBXSourcesBuildPhase }.first
        let resourcesBuildPhase = pbxTarget.buildPhases.filter { $0 is PBXResourcesBuildPhase }.first
        let sourcesFiles = sourcesBuildPhase?.files?.compactMap {
            $0.file?.nameOrPath
        } ?? []
        let resourcesFiles = resourcesBuildPhase?.files?.compactMap {
            $0.file?.nameOrPath
        } ?? []

        XCTAssertTrue(sourcesFiles.isEmpty)
        XCTAssertEqual(resourcesFiles, [
            "Model.xcdatamodeld",
        ])
    }

    // MARK: - Helpers

    private func createProductFileElements(for targets: [Target]) -> ProjectFileElements {
        let fileElements = ProjectFileElements()
        fileElements.products = Dictionary(uniqueKeysWithValues: targets.map {
            ($0.name, PBXFileReference(name: $0.name))
        })
        return fileElements
    }

    private func createLocalizedResourceFileElements(for files: [AbsolutePath]) -> ProjectFileElements {
        let fileElements = ProjectFileElements()
        fileElements.elements = Dictionary(uniqueKeysWithValues: files.map {
            ($0, PBXVariantGroup())
        })
        return fileElements
    }

    private func createFileElements(for files: [AbsolutePath]) -> ProjectFileElements {
        let fileElements = ProjectFileElements()
        fileElements.elements = Dictionary(uniqueKeysWithValues: files.map {
            ($0, PBXFileReference(sourceTree: .group, name: $0.basename))
        })
        return fileElements
    }

    private func createFileElements(for coreDataModels: [CoreDataModel]) -> ProjectFileElements {
        let fileElements = ProjectFileElements()
        coreDataModels.forEach { model in
            let versionGroup = XCVersionGroup(path: model.path.basename, name: model.path.basename)
            fileElements.elements[model.path] = versionGroup
            model.versions.forEach { version in
                let fileReference = PBXFileReference(name: version.basename, path: version.basename)
                fileElements.elements[version] = fileReference
            }
        }
        return fileElements
    }

    private func createFileElements(for headers: Headers) -> ProjectFileElements {
        createFileElements(for: headers.public + headers.private + headers.project)
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
