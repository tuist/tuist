import Basic
import Foundation
import TuistCoreTesting
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
    var graph: Graphing!

    override func setUp() {
        subject = BuildPhaseGenerator()
        errorHandler = MockErrorHandler()
        graph = Graph.test()
    }

    func test_generateBuildPhases_generatesActions() throws {
        let tmpDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let pbxTarget = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        let fileElements = ProjectFileElements()
        pbxproj.add(object: pbxTarget)

        let target = Target.test(sources: [],
                                 resources: [],
                                 actions: [
                                     TargetAction(name: "post", order: .post, path: tmpDir.path.appending(component: "script.sh"), arguments: ["arg"]),
                                     TargetAction(name: "pre", order: .pre, path: tmpDir.path.appending(component: "script.sh"), arguments: ["arg"]),
                                 ])

        try subject.generateBuildPhases(path: tmpDir.path,
                                        target: target,
                                        graph: Graph.test(),
                                        pbxTarget: pbxTarget,
                                        fileElements: fileElements,
                                        pbxproj: pbxproj,
                                        sourceRootPath: tmpDir.path)

        let preBuildPhase = pbxTarget.buildPhases.first as? PBXShellScriptBuildPhase
        XCTAssertEqual(preBuildPhase?.name, "pre")
        XCTAssertEqual(preBuildPhase?.shellPath, "/bin/sh")
        XCTAssertEqual(preBuildPhase?.shellScript, "script.sh arg")

        let postBuildPhase = pbxTarget.buildPhases.last as? PBXShellScriptBuildPhase
        XCTAssertEqual(postBuildPhase?.name, "post")
        XCTAssertEqual(postBuildPhase?.shellPath, "/bin/sh")
        XCTAssertEqual(postBuildPhase?.shellScript, "script.sh arg")
    }

    func test_generateSourcesBuildPhase() throws {
        let path = AbsolutePath("/test/file.swift")
        let target = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: target)
        let fileElements = ProjectFileElements()
        let fileReference = PBXFileReference(sourceTree: .group, name: "Test")
        pbxproj.add(object: fileReference)
        fileElements.elements[path] = fileReference

        try subject.generateSourcesBuildPhase(files: [path],
                                              pbxTarget: target,
                                              fileElements: fileElements,
                                              pbxproj: pbxproj)

        let buildPhase: PBXBuildPhase? = target.buildPhases.first
        XCTAssertNotNil(buildPhase)
        XCTAssertTrue(buildPhase is PBXSourcesBuildPhase)
        let pbxBuildFile: PBXBuildFile? = buildPhase?.files?.first
        XCTAssertNotNil(pbxBuildFile)
        XCTAssertEqual(pbxBuildFile?.file, fileReference)
    }

    func test_generateSourcesBuildPhase_throws_when_theFileReferenceIsMissing() {
        let path = AbsolutePath("/test/file.swift")
        let target = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: target)
        let fileElements = ProjectFileElements()

        XCTAssertThrowsError(try subject.generateSourcesBuildPhase(files: [path],
                                                                   pbxTarget: target,
                                                                   fileElements: fileElements,
                                                                   pbxproj: pbxproj)) {
            XCTAssertEqual($0 as? BuildPhaseGenerationError, BuildPhaseGenerationError.missingFileReference(path))
        }
    }

    func test_generateHeadersBuildPhase() throws {
        let path = AbsolutePath("/test.h")
        let headers = Headers.test(public: [path], private: [], project: [])
        let pbxproj = PBXProj()
        let fileElements = ProjectFileElements()
        let header = PBXFileReference()
        pbxproj.add(object: header)
        fileElements.elements[AbsolutePath("/test.h")] = header
        let target = PBXNativeTarget(name: "Test")

        try subject.generateHeadersBuildPhase(headers: headers,
                                              pbxTarget: target,
                                              fileElements: fileElements,
                                              pbxproj: pbxproj)

        let pbxBuildPhase: PBXBuildPhase? = target.buildPhases.first
        XCTAssertNotNil(pbxBuildPhase)
        XCTAssertTrue(pbxBuildPhase is PBXHeadersBuildPhase)
        let pbxBuildFile: PBXBuildFile? = pbxBuildPhase?.files?.first
        XCTAssertNotNil(pbxBuildFile)
        XCTAssertEqual(pbxBuildFile?.settings?["ATTRIBUTES"] as? [String], ["Public"])
        XCTAssertEqual(pbxBuildFile?.file, header)
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
        
        let target = Target.test(sources: ["/test/file.swift"],
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
        let path = AbsolutePath("/en.lproj/Main.storyboard")
        let target = Target.test(resources: [.file(path: path)])
        let fileElements = ProjectFileElements()
        let pbxproj = PBXProj()
        let group = PBXVariantGroup()
        pbxproj.add(object: group)
        fileElements.elements[AbsolutePath("/Main.storyboard")] = group
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
        XCTAssertEqual(pbxBuildFile?.file, group)
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

    // MARK: - Helpers

    private func createProductFileElements(for targets: [Target]) -> ProjectFileElements {
        let fileElements = ProjectFileElements()
        fileElements.products = Dictionary(uniqueKeysWithValues: targets.map {
            ($0.productNameWithExtension, PBXFileReference(name: $0.name))
        })
        return fileElements
    }
}
