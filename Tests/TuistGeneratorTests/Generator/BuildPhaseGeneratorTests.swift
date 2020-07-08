import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest
@testable import TuistGenerator

final class BuildPhaseGenerationErrorTests: XCTestCase {
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

final class BuildPhaseGeneratorTests: XCTestCase {
    var subject: BuildPhaseGenerator!
    var errorHandler: MockErrorHandler!
    var graph: Graph!

    override func setUp() {
        subject = BuildPhaseGenerator()
        errorHandler = MockErrorHandler()
        graph = Graph.test()
    }

    override func tearDown() {
        super.tearDown()

        subject = nil
        errorHandler = nil
        graph = nil
    }

    func test_generateSourcesBuildPhase() throws {
        // Given
        let target = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: target)

        let sources: [Target.SourceFile] = [
            ("/test/file1.swift", "flag"),
            ("/test/file2.swift", nil),
        ]

        let fileElements = createFileElements(for: sources.map { $0.path })

        // When
        try subject.generateSourcesBuildPhase(files: sources,
                                              pbxTarget: target,
                                              fileElements: fileElements,
                                              pbxproj: pbxproj)

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

    func test_generateSourcesBuildPhase_throws_when_theFileReferenceIsMissing() {
        let path = AbsolutePath("/test/file.swift")
        let target = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: target)
        let fileElements = ProjectFileElements()

        XCTAssertThrowsError(try subject.generateSourcesBuildPhase(files: [(path: path, compilerFlags: nil)],
                                                                   pbxTarget: target,
                                                                   fileElements: fileElements,
                                                                   pbxproj: pbxproj)) {
            XCTAssertEqual($0 as? BuildPhaseGenerationError, BuildPhaseGenerationError.missingFileReference(path))
        }
    }

    func test_generateSourcesBuildPhase_whenLocalizedFile() throws {
        // Given
        let target = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: target)

        let sources: [Target.SourceFile] = [
            ("/path/sources/Base.lproj/OTTSiriExtension.intentdefinition", nil),
            ("/path/sources/en.lproj/OTTSiriExtension.intentdefinition", nil),
        ]

        let fileElements = createLocalizedResourceFileElements(for: [
            "/path/sources/OTTSiriExtension.intentdefinition",
        ])

        // When
        try subject.generateSourcesBuildPhase(files: sources,
                                              pbxTarget: target,
                                              fileElements: fileElements,
                                              pbxproj: pbxproj)

        // Then
        let buildPhase = try target.sourcesBuildPhase()
        let buildFiles = buildPhase?.files ?? []

        XCTAssertEqual(buildFiles.map { $0.file }, [
            fileElements.elements["/path/sources/OTTSiriExtension.intentdefinition"],
        ])
    }

    func test_generateSourcesBuildPhase_throws_whenLocalizedFileAndFileReferenceIsMissing() {
        let path = AbsolutePath("/test/Base.lproj/file.intentdefinition")
        let target = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: target)
        let fileElements = ProjectFileElements()

        XCTAssertThrowsError(try subject.generateSourcesBuildPhase(files: [(path: path, compilerFlags: nil)],
                                                                   pbxTarget: target,
                                                                   fileElements: fileElements,
                                                                   pbxproj: pbxproj)) {
            XCTAssertEqual($0 as? BuildPhaseGenerationError, BuildPhaseGenerationError.missingFileReference(path))
        }
    }

    func test_generateHeadersBuildPhase() throws {
        // Given
        let target = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: target)

        let headers = Headers(public: ["/test/Public1.h"],
                              private: ["/test/Private1.h"],
                              project: ["/test/Project1.h"])

        let fileElements = createFileElements(for: headers)

        // When
        try subject.generateHeadersBuildPhase(headers: headers,
                                              pbxTarget: target,
                                              fileElements: fileElements,
                                              pbxproj: pbxproj)

        // Then
        let buildPhase = try XCTUnwrap(target.buildPhases.first as? PBXHeadersBuildPhase)
        let buildFiles = buildPhase.files ?? []

        struct FileWithSettings: Equatable {
            var name: String?
            var attributes: [String]?
        }

        let buildFilesWithSettings = buildFiles.map {
            FileWithSettings(name: $0.file?.name,
                             attributes: $0.settings?["ATTRIBUTES"] as? [String])
        }

        XCTAssertEqual(buildFilesWithSettings, [
            FileWithSettings(name: "Private1.h", attributes: ["Private"]),
            FileWithSettings(name: "Public1.h", attributes: ["Public"]),
            FileWithSettings(name: "Project1.h", attributes: nil),
        ])
    }

    func test_generateHeadersBuildPhase_before_generateSourceBuildPhase() throws {
        let tmpDir = try TemporaryDirectory(removeTreeOnDeinit: true)
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

        let target = Target.test(sources: [(path: "/test/file.swift", compilerFlags: nil)],
                                 headers: headers)

        try subject.generateBuildPhases(path: tmpDir.path,
                                        target: target,
                                        graph: Graph.test(),
                                        pbxTarget: pbxTarget,
                                        fileElements: fileElements,
                                        pbxproj: pbxproj,
                                        sourceRootPath: tmpDir.path)

        let firstBuildPhase: PBXBuildPhase? = pbxTarget.buildPhases.first
        XCTAssertNotNil(firstBuildPhase)
        XCTAssertTrue(firstBuildPhase is PBXHeadersBuildPhase)

        let secondBuildPhase: PBXBuildPhase? = pbxTarget.buildPhases[1]
        XCTAssertTrue(secondBuildPhase is PBXSourcesBuildPhase)
    }

    func test_generateResourcesBuildPhase_whenLocalizedFile() throws {
        // Given
        let files: [AbsolutePath] = [
            "/path/resources/en.lproj/Main.storyboard",
            "/path/resources/en.lproj/App.strings",
            "/path/resources/fr.lproj/Main.storyboard",
            "/path/resources/fr.lproj/App.strings",
        ]

        let resources = files.map { FileElement.file(path: $0) }
        let fileElements = createLocalizedResourceFileElements(for: [
            "/path/resources/Main.storyboard",
            "/path/resources/App.strings",
        ])

        let nativeTarget = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()

        // When
        try subject.generateResourcesBuildPhase(path: "/path",
                                                target: .test(resources: resources),
                                                graph: Graph.test(),
                                                pbxTarget: nativeTarget,
                                                fileElements: fileElements,
                                                pbxproj: pbxproj)

        // Then
        let buildPhase = nativeTarget.buildPhases.first
        XCTAssertEqual(buildPhase?.files?.map { $0.file }, [
            fileElements.elements["/path/resources/Main.storyboard"],
            fileElements.elements["/path/resources/App.strings"],
        ])
    }

    func test_generateResourcesBuildPhase_whenCoreDataModel() throws {
        let coreDataModel = CoreDataModel(path: AbsolutePath("/Model.xcdatamodeld"),
                                          versions: [AbsolutePath("/Model.xcdatamodeld/1.xcdatamodel")],
                                          currentVersion: "1")
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
        try subject.generateResourcesBuildPhase(path: "/path",
                                                target: target,
                                                graph: Graph.test(),
                                                pbxTarget: nativeTarget,
                                                fileElements: fileElements,
                                                pbxproj: pbxproj)

        let pbxBuildPhase: PBXBuildPhase? = nativeTarget.buildPhases.first
        XCTAssertNotNil(pbxBuildPhase)
        XCTAssertTrue(pbxBuildPhase is PBXResourcesBuildPhase)
        let pbxBuildFile: PBXBuildFile? = pbxBuildPhase?.files?.first
        XCTAssertEqual(pbxBuildFile?.file, versionGroup)
        XCTAssertEqual(versionGroup.currentVersion, model)
    }

    func test_generateResourcesBuildPhase_whenNormalResource() throws {
        let path = AbsolutePath("/image.png")
        let target = Target.test(resources: [.file(path: path)])
        let fileElements = ProjectFileElements()
        let pbxproj = PBXProj()
        let fileElement = PBXFileReference()
        pbxproj.add(object: fileElement)
        fileElements.elements[path] = fileElement
        let nativeTarget = PBXNativeTarget(name: "Test")

        try subject.generateResourcesBuildPhase(path: "/path",
                                                target: target,
                                                graph: Graph.test(),
                                                pbxTarget: nativeTarget,
                                                fileElements: fileElements,
                                                pbxproj: pbxproj)

        let pbxBuildPhase: PBXBuildPhase? = nativeTarget.buildPhases.first
        XCTAssertNotNil(pbxBuildPhase)
        XCTAssertTrue(pbxBuildPhase is PBXResourcesBuildPhase)
        let pbxBuildFile: PBXBuildFile? = pbxBuildPhase?.files?.first
        XCTAssertEqual(pbxBuildFile?.file, fileElement)
    }

    func test_generateResourceBundle() throws {
        // Given
        let path = AbsolutePath("/path")
        let bundle1 = Target.test(name: "Bundle1", product: .bundle)
        let bundle2 = Target.test(name: "Bundle2", product: .bundle)
        let app = Target.test(name: "App", product: .app)
        let graph = Graph.create(project: .test(path: path),
                                 dependencies: [
                                     (target: bundle1, dependencies: []),
                                     (target: bundle2, dependencies: []),
                                     (target: app, dependencies: [bundle1, bundle2]),
                                 ])

        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createProductFileElements(for: [bundle1, bundle2])

        // When
        try subject.generateResourcesBuildPhase(path: path,
                                                target: app,
                                                graph: graph,
                                                pbxTarget: nativeTarget,
                                                fileElements: fileElements,
                                                pbxproj: pbxproj)

        // Then
        let resourcePhase = try nativeTarget.resourcesBuildPhase()
        XCTAssertEqual(resourcePhase?.files?.compactMap { $0.file?.nameOrPath }, [
            "Bundle1",
            "Bundle2",
        ])
    }

    func test_generateResourceBundle_fromProjectDependency() throws {
        // Given
        let bundle = Target.test(name: "Bundle1", product: .bundle)
        let projectA = Project.test(path: "/path/a")

        let app = Target.test(name: "App", product: .app)
        let projectB = Project.test(path: "/path/b")

        let graph = Graph.create(projects: [projectA, projectB],
                                 dependencies: [
                                     (project: projectA, target: bundle, dependencies: []),
                                     (project: projectB, target: app, dependencies: [bundle]),
                                 ])

        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createProductFileElements(for: [bundle])

        // When
        try subject.generateResourcesBuildPhase(path: projectB.path,
                                                target: app,
                                                graph: graph,
                                                pbxTarget: nativeTarget,
                                                fileElements: fileElements,
                                                pbxproj: pbxproj)

        // Then
        let resourcePhase = try nativeTarget.resourcesBuildPhase()
        XCTAssertEqual(resourcePhase?.files?.compactMap { $0.file?.nameOrPath }, [
            "Bundle1",
        ])
    }

    func test_generateAppExtensionsBuildPhase() throws {
        let appExtension = Target.test(name: "AppExtension", product: .appExtension)
        let projectA = Project.test(path: "/path/a")
        let stickerPackExtension = Target.test(name: "StickerPackExtension", product: .stickerPackExtension)
        let projectB = Project.test(path: "/path/b")
        let app = Target.test(name: "App", product: .app)
        let projectC = Project.test(path: "/path/c")
        let graph = Graph.create(projects: [projectA, projectB, projectC],
                                 dependencies: [
                                     (project: projectA, target: appExtension, dependencies: []),
                                     (project: projectB, target: stickerPackExtension, dependencies: []),
                                     (project: projectC, target: app, dependencies: [appExtension, stickerPackExtension]),
                                 ])
        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createProductFileElements(for: [appExtension, stickerPackExtension])

        try subject.generateAppExtensionsBuildPhase(path: projectC.path,
                                                    target: app,
                                                    graph: graph,
                                                    pbxTarget: nativeTarget,
                                                    fileElements: fileElements,
                                                    pbxproj: pbxproj)

        let pbxBuildPhase: PBXBuildPhase? = nativeTarget.buildPhases.first
        XCTAssertNotNil(pbxBuildPhase)
        XCTAssertTrue(pbxBuildPhase is PBXCopyFilesBuildPhase)
        XCTAssertEqual(pbxBuildPhase?.files?.compactMap { $0.file?.nameOrPath }, [
            "AppExtension",
            "StickerPackExtension",
        ])
        XCTAssertEqual(pbxBuildPhase?.files?.compactMap { $0.settings as? [String: [String]] },
                       [["ATTRIBUTES": ["RemoveHeadersOnCopy"]],
                        ["ATTRIBUTES": ["RemoveHeadersOnCopy"]]])
    }

    func test_generateAppExtensionsBuildPhase_noBuildPhase_when_appDoesntHaveAppExtensions() throws {
        let app = Target.test(name: "App", product: .app)
        let project = Project.test()
        let graph = Graph.create(projects: [project],
                                 dependencies: [])
        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = ProjectFileElements()

        try subject.generateAppExtensionsBuildPhase(path: project.path,
                                                    target: app,
                                                    graph: graph,
                                                    pbxTarget: nativeTarget,
                                                    fileElements: fileElements,
                                                    pbxproj: pbxproj)

        XCTAssertTrue(nativeTarget.buildPhases.isEmpty)
    }

    func test_generateWatchBuildPhase() throws {
        // Given
        let app = Target.test(name: "App", product: .app)
        let watchApp = Target.test(name: "WatchApp", product: .watch2App)
        let project = Project.test()
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: app, dependencies: [watchApp]),
                                     (target: watchApp, dependencies: []),
                                 ])
        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createProductFileElements(for: [app, watchApp])

        // When
        try subject.generateEmbedWatchBuildPhase(path: project.path,
                                                 target: app,
                                                 graph: graph,
                                                 pbxTarget: nativeTarget,
                                                 fileElements: fileElements,
                                                 pbxproj: pbxproj)
        // Then
        let pbxBuildPhase = try XCTUnwrap(nativeTarget.buildPhases.first as? PBXCopyFilesBuildPhase)
        XCTAssertEqual(pbxBuildPhase.files?.compactMap { $0.file?.nameOrPath }, [
            "WatchApp",
        ])
        XCTAssertEqual(pbxBuildPhase.files?.compactMap { $0.settings as? [String: [String]] },
                       [["ATTRIBUTES": ["RemoveHeadersOnCopy"]]])
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

    private func createFileElements(for headers: Headers) -> ProjectFileElements {
        createFileElements(for: headers.public + headers.private + headers.project)
    }
}
