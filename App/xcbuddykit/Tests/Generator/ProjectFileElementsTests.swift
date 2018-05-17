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
        let sourcesPhase = SourcesBuildPhase(buildFiles: BuildFiles(files: Set([AbsolutePath("/project/file.swift")])))
        let resourcesPhase = ResourcesBuildPhase(buildFiles: BuildFiles(files: Set([AbsolutePath("/project/image.png")])))
        let headersPhase = HeadersBuildPhase(public: BuildFiles(files: Set([AbsolutePath("/project/public.h")])),
                                             project: BuildFiles(files: Set([AbsolutePath("/project/project.h")])),
                                             private: BuildFiles(files: Set([AbsolutePath("/project/private.h")])))
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

    func test_closestRelativeElementPath() {
        let got = subject.closestRelativeElementPath(path: AbsolutePath("/a/framework/framework.framework"),
                                                     sourceRootPath: AbsolutePath("/a/b/c/project"))
        XCTAssertEqual(got, RelativePath("../../../framework"))
    }
}
