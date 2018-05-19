import Basic
import Foundation
@testable import xcbuddykit
@testable import xcodeproj
import XCTest

final class ProjectFileElementsTests: XCTestCase {
    var subject: ProjectFileElements!

    override func setUp() {
        super.setUp()
        subject = ProjectFileElements()
    }

    func test_projectFiles() {
        let settings = Settings(base: [:],
                                debug: Configuration(settings: [:],
                                                     xcconfig: AbsolutePath("/project/debug.xcconfig")),
                                release: Configuration(settings: [:],
                                                       xcconfig: AbsolutePath("/project/release.xcconfig")))

        let project = Project.test(path: AbsolutePath("/project/"), settings: settings)
        let files = subject.projectFiles(project: project)
        XCTAssertTrue(files.contains(AbsolutePath("/project/debug.xcconfig")))
        XCTAssertTrue(files.contains(AbsolutePath("/project/release.xcconfig")))
    }

    func test_targetFiles() {
        let settings = Settings(base: [:],
                                debug: Configuration(settings: [:],
                                                     xcconfig: AbsolutePath("/project/debug.xcconfig")),
                                release: Configuration(settings: [:],
                                                       xcconfig: AbsolutePath("/project/release.xcconfig")))
        var buildPhases: [xcbuddykit.BuildPhase] = []
        let sourcesPhase = SourcesBuildPhase(buildFiles: [SourcesBuildFile([AbsolutePath("/project/file.swift")])])
        let resourcesPhase = ResourcesBuildPhase(buildFiles: [
            ResourcesBuildFile([AbsolutePath("/project/image.png")]),
            CoreDataModelBuildFile(AbsolutePath("/project/model.xcdatamodeld"),
                                   currentVersion: "1",
                                   versions: [AbsolutePath("/project/model.xcdatamodeld/1.xcdatamodel")]),
        ])
        let headersPhase = HeadersBuildPhase(buildFiles: [
            HeadersBuildFile([AbsolutePath("/project/public.h")], accessLevel: .public),
            HeadersBuildFile([AbsolutePath("/project/project.h")], accessLevel: .project),
            HeadersBuildFile([AbsolutePath("/project/private.h")], accessLevel: .private),
        ])
        buildPhases.append(sourcesPhase)
        buildPhases.append(resourcesPhase)
        buildPhases.append(headersPhase)
        let target = Target(name: "target",
                            platform: .ios,
                            product: .app,
                            bundleId: "com.bundle.id",
                            infoPlist: AbsolutePath("/project/info.plist"),
                            entitlements: AbsolutePath("/project/app.entitlements"),
                            settings: settings,
                            buildPhases: buildPhases,
                            dependencies: [])
        let files = subject.targetFiles(target: target)
        XCTAssertTrue(files.contains(AbsolutePath("/project/debug.xcconfig")))
        XCTAssertTrue(files.contains(AbsolutePath("/project/release.xcconfig")))
        XCTAssertTrue(files.contains(AbsolutePath("/project/file.swift")))
        XCTAssertTrue(files.contains(AbsolutePath("/project/image.png")))
        XCTAssertTrue(files.contains(AbsolutePath("/project/public.h")))
        XCTAssertTrue(files.contains(AbsolutePath("/project/project.h")))
        XCTAssertTrue(files.contains(AbsolutePath("/project/private.h")))
        XCTAssertTrue(files.contains(AbsolutePath("/project/model.xcdatamodeld/1.xcdatamodel")))
        XCTAssertTrue(files.contains(AbsolutePath("/project/model.xcdatamodeld")))
    }

    func test_generatePath() throws {
        let pbxproj = PBXProj()
        let path = AbsolutePath("/a/b/c/file.swift")
        let project = Project.test()
        let sourceRootPath = AbsolutePath("/a/project/")
        let groups = ProjectGroups.generate(project: project,
                                            objects: pbxproj.objects,
                                            sourceRootPath: sourceRootPath)
        subject.generate(path: path,
                         groups: groups,
                         objects: pbxproj.objects,
                         sourceRootPath: sourceRootPath)

        let projectGroup = groups.project

        let bGroup: PBXGroup = try projectGroup.children.first!.object()
        XCTAssertEqual(bGroup.name, "b")
        XCTAssertEqual(bGroup.path, "../b")
        XCTAssertEqual(bGroup.sourceTree, .group)

        let cGroup: PBXGroup = try bGroup.children.first!.object()
        XCTAssertEqual(cGroup.path, "c")
        XCTAssertNil(cGroup.name)
        XCTAssertEqual(cGroup.sourceTree, .group)

        let file: PBXFileReference = try cGroup.children.first!.object()
        XCTAssertEqual(file.path, "file.swift")
        XCTAssertNil(file.name)
        XCTAssertEqual(file.sourceTree, .group)
    }

    func test_addVariantGroupElement() throws {
        let from = AbsolutePath("/project/")
        let folderAbsolutePath = AbsolutePath("/project/en.lproj")
        let folderRelativePath = RelativePath("./en.lproj")
        let group = PBXGroup()
        let objects = PBXObjects(objects: [:])
        objects.addObject(group)
        _ = subject.addVariantGroupElement(from: from,
                                           folderAbsolutePath: folderAbsolutePath,
                                           folderRelativePath: folderRelativePath,
                                           name: nil,
                                           toGroup: group,
                                           objects: objects)
        let variantGroup: PBXVariantGroup? = try group.children.first?.object()
        XCTAssertEqual(variantGroup?.path, "en.lproj")
        XCTAssertEqual(variantGroup?.sourceTree, .group)
        XCTAssertNil(variantGroup?.name)
    }

    func test_addVersionGroupElement() throws {
        let from = AbsolutePath("/project/")
        let folderAbsolutePath = AbsolutePath("/project/model.xcdatamodel")
        let folderRelativePath = RelativePath("./model.xcdatamodel")
        let group = PBXGroup()
        let objects = PBXObjects(objects: [:])
        objects.addObject(group)
        _ = subject.addVersionGroupElement(from: from,
                                           folderAbsolutePath: folderAbsolutePath,
                                           folderRelativePath: folderRelativePath,
                                           name: nil,
                                           toGroup: group,
                                           objects: objects)
        let versionGroup: XCVersionGroup? = try group.children.first?.object()
        XCTAssertEqual(versionGroup?.path, "model.xcdatamodel")
        XCTAssertEqual(versionGroup?.sourceTree, .group)
        XCTAssertNil(versionGroup?.name)
        XCTAssertEqual(versionGroup?.versionGroupType, Xcode.filetype(extension: "xcdatamodel"))
    }

    func test_addFileElement() throws {
        let from = AbsolutePath("/project/")
        let fileAbsolutePath = AbsolutePath("/project/file.swift")
        let fileRelativePath = RelativePath("./file.swift")
        let group = PBXGroup()
        let objects = PBXObjects(objects: [:])
        objects.addObject(group)
        _ = subject.addFileElement(from: from,
                                   fileAbsolutePath: fileAbsolutePath,
                                   fileRelativePath: fileRelativePath,
                                   name: nil,
                                   toGroup: group,
                                   objects: objects)
        let file: PBXFileReference? = try group.children.first?.object()
        XCTAssertEqual(file?.path, "file.swift")
        XCTAssertEqual(file?.sourceTree, .group)
        XCTAssertNil(file?.name)
        XCTAssertEqual(file?.lastKnownFileType, Xcode.filetype(extension: "swift"))
    }

    func test_group() {
        let group = PBXGroup()
        let path = AbsolutePath("/path/to/folder")
        subject.elements[path] = group
        XCTAssertEqual(subject.group(path: path), group)
    }

    func test_file() {
        let file = PBXFileReference()
        let path = AbsolutePath("/path/to/folder")
        subject.elements[path] = file
        XCTAssertEqual(subject.file(path: path), file)
    }

    func test_isVersionGroup() {
        let path = AbsolutePath("/path/to/model.xcdatamodeld")
        XCTAssertTrue(subject.isVersionGroup(path: path))
    }

    func test_isVariantGroup() {
        let path = AbsolutePath("/path/to/en.lproj")
        XCTAssertTrue(subject.isVariantGroup(path: path))
    }

    func test_isGroup() {
        let path = AbsolutePath("/path/to/folder")
        XCTAssertTrue(subject.isGroup(path: path))
    }

    func test_closestRelativeElementPath() {
        let got = subject.closestRelativeElementPath(path: AbsolutePath("/a/framework/framework.framework"),
                                                     sourceRootPath: AbsolutePath("/a/b/c/project"))
        XCTAssertEqual(got, RelativePath("../../../framework"))
    }
}
