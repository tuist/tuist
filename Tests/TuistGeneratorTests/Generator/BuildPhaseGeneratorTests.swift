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

        try subject.generateBuildPhases(target: target,
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

    func test_generateResourcesBuildPhase_whenLocalizedFile() throws {
        let path = AbsolutePath("/en.lproj/Main.storyboard")
        let fileElements = ProjectFileElements()
        let pbxproj = PBXProj()
        let group = PBXVariantGroup()
        pbxproj.add(object: group)
        fileElements.elements[AbsolutePath("/Main.storyboard")] = group
        let target = PBXNativeTarget(name: "Test")

        try subject.generateResourcesBuildPhase(files: [path],
                                                coreDataModels: [],
                                                pbxTarget: target,
                                                fileElements: fileElements,
                                                pbxproj: pbxproj)

        let pbxBuildPhase: PBXBuildPhase? = target.buildPhases.first
        XCTAssertNotNil(pbxBuildPhase)
        XCTAssertTrue(pbxBuildPhase is PBXResourcesBuildPhase)
        let pbxBuildFile: PBXBuildFile? = pbxBuildPhase?.files?.first
        XCTAssertEqual(pbxBuildFile?.file, group)
    }

    func test_generateResourcesBuildPhase_whenCoreDataModel() throws {
        let coreDataModel = CoreDataModel(path: AbsolutePath("/Model.xcdatamodeld"),
                                          versions: [AbsolutePath("/Model.xcdatamodeld/1.xcdatamodel")],
                                          currentVersion: "1")
        let fileElements = ProjectFileElements()
        let pbxproj = PBXProj()

        let versionGroup = XCVersionGroup()
        pbxproj.add(object: versionGroup)
        fileElements.elements[AbsolutePath("/Model.xcdatamodeld")] = versionGroup

        let model = PBXFileReference()
        pbxproj.add(object: model)
        versionGroup.children.append(model)
        fileElements.elements[AbsolutePath("/Model.xcdatamodeld/1.xcdatamodel")] = model

        let target = PBXNativeTarget(name: "Test")
        try subject.generateResourcesBuildPhase(files: [],
                                                coreDataModels: [coreDataModel],
                                                pbxTarget: target,
                                                fileElements: fileElements,
                                                pbxproj: pbxproj)

        let pbxBuildPhase: PBXBuildPhase? = target.buildPhases.first
        XCTAssertNotNil(pbxBuildPhase)
        XCTAssertTrue(pbxBuildPhase is PBXResourcesBuildPhase)
        let pbxBuildFile: PBXBuildFile? = pbxBuildPhase?.files?.first
        XCTAssertEqual(pbxBuildFile?.file, versionGroup)
        XCTAssertEqual(versionGroup.currentVersion, model)
    }

    func test_generateResourcesBuildPhase_whenNormalResource() throws {
        let path = AbsolutePath("/image.png")
        let fileElements = ProjectFileElements()
        let pbxproj = PBXProj()
        let fileElement = PBXFileReference()
        pbxproj.add(object: fileElement)
        fileElements.elements[path] = fileElement
        let target = PBXNativeTarget(name: "Test")

        try subject.generateResourcesBuildPhase(files: [path],
                                                coreDataModels: [],
                                                pbxTarget: target,
                                                fileElements: fileElements,
                                                pbxproj: pbxproj)

        let pbxBuildPhase: PBXBuildPhase? = target.buildPhases.first
        XCTAssertNotNil(pbxBuildPhase)
        XCTAssertTrue(pbxBuildPhase is PBXResourcesBuildPhase)
        let pbxBuildFile: PBXBuildFile? = pbxBuildPhase?.files?.first
        XCTAssertEqual(pbxBuildFile?.file, fileElement)
    }
}
