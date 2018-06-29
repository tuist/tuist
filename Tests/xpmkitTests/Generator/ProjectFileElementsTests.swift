import Basic
import Foundation
@testable import xcodeproj
import XCTest
@testable import xpmkit

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

    func test_targetProducts() {
        let target = Target.test(buildPhases: [
            CopyBuildPhase(name: "Copy",
                           destination: .frameworks,
                           files: [.product("Test.framework")]),
        ])
        let products = subject.targetProducts(target: target).sorted()
        XCTAssertEqual(products.first, "Target.app")
        XCTAssertEqual(products.last, "Test.framework")
    }

    func test_targetFiles() {
        let settings = Settings(base: [:],
                                debug: Configuration(settings: [:],
                                                     xcconfig: AbsolutePath("/project/debug.xcconfig")),
                                release: Configuration(settings: [:],
                                                       xcconfig: AbsolutePath("/project/release.xcconfig")))
        var buildPhases: [xpmkit.BuildPhase] = []
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
                            platform: .iOS,
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

    func test_generateProduct() {
        let pbxproj = PBXProj()
        let project = Project.test()
        let sourceRootPath = AbsolutePath("/a/project/")
        let groups = ProjectGroups.generate(project: project,
                                            objects: pbxproj.objects,
                                            sourceRootPath: sourceRootPath)
        let products = ["Test.framework"]
        let objects = PBXObjects()
        subject.generate(products: products,
                         groups: groups,
                         objects: objects)
        XCTAssertEqual(groups.products.childrenReferences.count, 1)
        let fileReference = subject.product(name: "Test.framework")
        XCTAssertNotNil(fileReference)
        XCTAssertEqual(fileReference?.sourceTree, .buildProductsDir)
        XCTAssertEqual(fileReference?.path, "Test.framework")
        XCTAssertNil(fileReference?.name)
        XCTAssertEqual(fileReference?.includeInIndex, false)
    }

    func test_generateDependencies_whenTargetNode_thatHasAlreadyBeenAdded() throws {
        let pbxproj = PBXProj()
        let sourceRootPath = AbsolutePath("/a/project/")
        let path = AbsolutePath("/test")
        let target = Target.test()
        let project = Project.test(path: path, targets: [target])
        let groups = ProjectGroups.generate(project: project,
                                            objects: pbxproj.objects,
                                            sourceRootPath: sourceRootPath)
        let objects = PBXObjects()
        var dependencies: Set<GraphNode> = Set()
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [])
        dependencies.insert(targetNode)

        subject.generate(dependencies: dependencies,
                         path: path,
                         groups: groups,
                         objects: objects,
                         sourceRootPath: sourceRootPath)

        XCTAssertEqual(groups.products.childrenReferences.count, 0)
    }

    func test_generateDependencies_whenTargetNode() throws {
        let pbxproj = PBXProj()
        let sourceRootPath = AbsolutePath("/a/project/")
        let path = AbsolutePath("/test")
        let target = Target.test()
        let project = Project.test(path: AbsolutePath("/waka"), targets: [target])
        let groups = ProjectGroups.generate(project: project,
                                            objects: pbxproj.objects,
                                            sourceRootPath: sourceRootPath)
        let objects = PBXObjects()
        var dependencies: Set<GraphNode> = Set()
        let targetNode = TargetNode(project: project,
                                    target: target,
                                    dependencies: [])
        dependencies.insert(targetNode)

        subject.generate(dependencies: dependencies,
                         path: path,
                         groups: groups,
                         objects: objects,
                         sourceRootPath: sourceRootPath)

        let fileReference: PBXFileReference? = try groups.products.childrenReferences.first?.object()
        XCTAssertEqual(fileReference?.sourceTree, .buildProductsDir)
        XCTAssertEqual(fileReference?.includeInIndex, false)
        XCTAssertEqual(fileReference?.path, "Target.app")
        XCTAssertEqual(fileReference?.explicitFileType, "wrapper.application")
    }

    func test_generateDependencies_whenPrecompiledNode() throws {
        let pbxproj = PBXProj()
        let sourceRootPath = AbsolutePath("/")
        let target = Target.test()
        let project = Project.test(path: AbsolutePath("/"), targets: [target])
        let groups = ProjectGroups.generate(project: project,
                                            objects: pbxproj.objects,
                                            sourceRootPath: sourceRootPath)
        let objects = PBXObjects()
        var dependencies: Set<GraphNode> = Set()
        let precompiledNode = FrameworkNode(path: project.path.appending(component: "waka.framework"))
        dependencies.insert(precompiledNode)

        subject.generate(dependencies: dependencies,
                         path: project.path,
                         groups: groups,
                         objects: objects,
                         sourceRootPath: sourceRootPath)

        let fileReference: PBXFileReference? = try groups.project.childrenReferences.first?.object()
        XCTAssertEqual(fileReference?.path, "waka.framework")
        XCTAssertEqual(fileReference?.path, "waka.framework")
        XCTAssertNil(fileReference?.name)
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

        let bGroup: PBXGroup = try projectGroup.childrenReferences.first!.object()
        XCTAssertEqual(bGroup.name, "b")
        XCTAssertEqual(bGroup.path, "../b")
        XCTAssertEqual(bGroup.sourceTree, .group)

        let cGroup: PBXGroup = try bGroup.childrenReferences.first!.object()
        XCTAssertEqual(cGroup.path, "c")
        XCTAssertNil(cGroup.name)
        XCTAssertEqual(cGroup.sourceTree, .group)

        let file: PBXFileReference = try cGroup.childrenReferences.first!.object()
        XCTAssertEqual(file.path, "file.swift")
        XCTAssertNil(file.name)
        XCTAssertEqual(file.sourceTree, .group)
    }

    func test_addVariantGroup() throws {
        let fileName = "localizable.strings"
        let dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let localizedDir = dir.path.appending(component: "en.lproj")
        try localizedDir.mkpath()
        try localizedDir.appending(component: fileName).write("test")
        let from = dir.path.parentDirectory
        let absolutePath = localizedDir
        let relativePath = RelativePath("en.lproj")
        let group = PBXGroup()
        let objects = PBXObjects()
        objects.addObject(group)
        subject.addVariantGroup(from: from,
                                absolutePath: absolutePath,
                                relativePath: relativePath,
                                toGroup: group,
                                objects: objects)
        let variantGroupPath = dir.path.appending(component: fileName)
        let variantGroup: PBXVariantGroup = subject.group(path: variantGroupPath) as! PBXVariantGroup
        XCTAssertEqual(variantGroup.name, fileName)
        XCTAssertEqual(variantGroup.sourceTree, .group)

        let fileReference: PBXFileReference? = try variantGroup.childrenReferences.first?.object()
        XCTAssertEqual(fileReference?.name, "en")
        XCTAssertEqual(fileReference?.sourceTree, .group)
        XCTAssertEqual(fileReference?.path, "en.lproj/\(fileName)")
    }

    func test_addVersionGroupElement() throws {
        let from = AbsolutePath("/project/")
        let folderAbsolutePath = AbsolutePath("/project/model.xcdatamodel")
        let folderRelativePath = RelativePath("./model.xcdatamodel")
        let group = PBXGroup()
        let objects = PBXObjects()
        objects.addObject(group)
        _ = subject.addVersionGroupElement(from: from,
                                           folderAbsolutePath: folderAbsolutePath,
                                           folderRelativePath: folderRelativePath,
                                           name: nil,
                                           toGroup: group,
                                           objects: objects)
        let versionGroup: XCVersionGroup? = try group.childrenReferences.first?.object()
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
        let objects = PBXObjects()
        objects.addObject(group)
        _ = subject.addFileElement(from: from,
                                   fileAbsolutePath: fileAbsolutePath,
                                   fileRelativePath: fileRelativePath,
                                   name: nil,
                                   toGroup: group,
                                   objects: objects)
        let file: PBXFileReference? = try group.childrenReferences.first?.object()
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

    func test_isLocalized() {
        let path = AbsolutePath("/path/to/es.lproj")
        XCTAssertTrue(subject.isLocalized(path: path))
    }

    func test_isVersionGroup() {
        let path = AbsolutePath("/path/to/model.xcdatamodeld")
        XCTAssertTrue(subject.isVersionGroup(path: path))
    }

    func test_isGroup() {
        let path = AbsolutePath("/path/to/folder")
        XCTAssertTrue(subject.isGroup(path: path))
    }

    func test_normalize_whenLocalized() {
        let path = AbsolutePath("/test/es.lproj/Main.storyboard")
        let normalized = subject.normalize(path)
        XCTAssertEqual(normalized, AbsolutePath("/test/es.lproj"))
    }

    func test_normalize() {
        let path = AbsolutePath("/test/file.swift")
        let normalized = subject.normalize(path)
        XCTAssertEqual(normalized, path)
    }

    func test_closestRelativeElementPath() {
        let got = subject.closestRelativeElementPath(path: AbsolutePath("/a/framework/framework.framework"),
                                                     sourceRootPath: AbsolutePath("/a/b/c/project"))
        XCTAssertEqual(got, RelativePath("../../../framework"))
    }
}
