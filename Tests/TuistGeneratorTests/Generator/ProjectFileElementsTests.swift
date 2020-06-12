import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class ProjectFileElementsTests: TuistUnitTestCase {
    var subject: ProjectFileElements!
    var playgrounds: MockPlaygrounds!
    var groups: ProjectGroups!
    var pbxproj: PBXProj!

    override func setUp() {
        super.setUp()
        playgrounds = MockPlaygrounds()
        pbxproj = PBXProj()
        groups = ProjectGroups.generate(project: .test(),
                                        pbxproj: pbxproj,
                                        xcodeprojPath: "/path/Project.xcodeproj",
                                        sourceRootPath: "/path",
                                        playgrounds: MockPlaygrounds())

        subject = ProjectFileElements(playgrounds: playgrounds)
    }

    override func tearDown() {
        playgrounds = nil
        pbxproj = nil
        groups = nil
        subject = nil
        super.tearDown()
    }

    func test_projectFiles() {
        // Given
        let settings = Settings(
            base: [:],
            configurations: [
                .debug: Configuration(xcconfig: AbsolutePath("/project/debug.xcconfig")),
                .release: Configuration(xcconfig: AbsolutePath("/project/release.xcconfig")),
            ]
        )

        let project = Project.test(path: AbsolutePath("/project/"),
                                   settings: settings,
                                   additionalFiles: [
                                       .file(path: "/path/to/file"),
                                       .folderReference(path: "/path/to/folder"),
                                   ])

        // When
        let files = subject.projectFiles(project: project)

        // Then
        XCTAssertTrue(files.isSuperset(of: [
            GroupFileElement(path: "/project/debug.xcconfig", group: project.filesGroup),
            GroupFileElement(path: "/project/release.xcconfig", group: project.filesGroup),
            GroupFileElement(path: "/path/to/file", group: project.filesGroup),
            GroupFileElement(path: "/path/to/folder", group: project.filesGroup, isReference: true),
        ]))
    }

    func test_addElement() throws {
        // Given
        let element = GroupFileElement(path: "/path/myfolder/resources/a.png",
                                       group: .group(name: "Project"))

        // When
        try subject.generate(fileElement: element,
                             groups: groups,
                             pbxproj: pbxproj,
                             sourceRootPath: "/path")

        // Then
        let projectGroup = groups.sortedMain.group(named: "Project")
        XCTAssertEqual(projectGroup?.flattenedChildren, [
            "myfolder/resources/a.png",
        ])
    }

    func test_addElement_withDotFolders() throws {
        // Given
        let element = GroupFileElement(path: "/path/my.folder/resources/a.png",
                                       group: .group(name: "Project"))

        // When
        try subject.generate(fileElement: element,
                             groups: groups,
                             pbxproj: pbxproj,
                             sourceRootPath: "/path")

        // Then
        let projectGroup = groups.sortedMain.group(named: "Project")
        XCTAssertEqual(projectGroup?.flattenedChildren, [
            "my.folder/resources/a.png",
        ])
    }

    func test_addElement_fileReference() throws {
        // Given
        let element = GroupFileElement(path: "/path/myfolder/resources/generated_images",
                                       group: .group(name: "Project"),
                                       isReference: true)

        // When
        try subject.generate(fileElement: element,
                             groups: groups,
                             pbxproj: pbxproj,
                             sourceRootPath: "/path")

        // Then
        let projectGroup = groups.sortedMain.group(named: "Project")
        XCTAssertEqual(projectGroup?.flattenedChildren, [
            "myfolder/resources/generated_images",
        ])
    }

    func test_addElement_parentDirectories() throws {
        // Given
        let element = GroupFileElement(path: "/path/another/path/resources/a.png",
                                       group: .group(name: "Project"))

        // When
        try subject.generate(fileElement: element,
                             groups: groups,
                             pbxproj: pbxproj,
                             sourceRootPath: "/path/project")

        // Then
        let projectGroup = groups.sortedMain.group(named: "Project")
        XCTAssertEqual(projectGroup?.flattenedChildren, [
            "another/path/resources/a.png",
        ])
    }

    func test_addElement_xcassets() throws {
        // Given
        let element = GroupFileElement(path: "/path/myfolder/resources/assets.xcassets/foo/bar.png",
                                       group: .group(name: "Project"))

        // When
        try subject.generate(fileElement: element,
                             groups: groups,
                             pbxproj: pbxproj,
                             sourceRootPath: "/path")

        // Then
        let projectGroup = groups.sortedMain.group(named: "Project")
        XCTAssertEqual(projectGroup?.flattenedChildren, [
            "myfolder/resources/assets.xcassets",
        ])
    }

    func test_addElement_xcassets_multiple_files() throws {
        // Given
        let resouces = [
            "/path/myfolder/resources/assets.xcassets/foo/a.png",
            "/path/myfolder/resources/assets.xcassets/foo/abc/b.png",
            "/path/myfolder/resources/assets.xcassets/foo/def/c.png",
            "/path/myfolder/resources/assets.xcassets",
        ]
        let elements = resouces.map {
            GroupFileElement(path: AbsolutePath($0),
                             group: .group(name: "Project"))
        }

        // When
        try elements.forEach {
            try subject.generate(fileElement: $0,
                                 groups: groups,
                                 pbxproj: pbxproj,
                                 sourceRootPath: "/path")
        }

        // Then
        let projectGroup = groups.sortedMain.group(named: "Project")
        XCTAssertEqual(projectGroup?.flattenedChildren, [
            "myfolder/resources/assets.xcassets",
        ])
    }

    func test_addElement_lproj_multiple_files() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let resouces = try createFiles([
            "resources/en.lproj/App.strings",
            "resources/en.lproj/Extension.strings",
            "resources/fr.lproj/App.strings",
            "resources/fr.lproj/Extension.strings",
        ])

        let elements = resouces.map {
            GroupFileElement(path: $0,
                             group: .group(name: "Project"),
                             isReference: true)
        }

        // When
        try elements.forEach {
            try subject.generate(fileElement: $0,
                                 groups: groups,
                                 pbxproj: pbxproj,
                                 sourceRootPath: temporaryPath)
        }

        // Then
        let projectGroup = groups.sortedMain.group(named: "Project")
        XCTAssertEqual(projectGroup?.flattenedChildren, [
            "resources/App.strings/en",
            "resources/App.strings/fr",
            "resources/Extension.strings/en",
            "resources/Extension.strings/fr",
        ])

        XCTAssertEqual(projectGroup?.debugVariantGroupPaths, [
            "resources/App.strings",
            "resources/Extension.strings",
        ])
    }

    func test_addElement_lproj_knownRegions() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let resouces = try createFiles([
            "resources/en.lproj/App.strings",
            "resources/en.lproj/Extension.strings",
            "resources/fr.lproj/App.strings",
            "resources/fr.lproj/Extension.strings",
            "resources/Base.lproj/App.strings",
            "resources/Base.lproj/Extension.strings",
        ])

        let elements = resouces.map {
            GroupFileElement(path: $0,
                             group: .group(name: "Project"),
                             isReference: true)
        }

        // When
        try elements.forEach {
            try subject.generate(fileElement: $0,
                                 groups: groups,
                                 pbxproj: pbxproj,
                                 sourceRootPath: temporaryPath)
        }

        // Then

        XCTAssertEqual(subject.knownRegions, Set([
            "en",
            "fr",
            "Base",
        ]))
    }

    func test_targetFiles() throws {
        // Given
        let settings = Settings.test(
            base: [:],
            debug: Configuration(settings: ["Configuration": "A"], xcconfig: AbsolutePath("/project/debug.xcconfig")),
            release: Configuration(settings: ["Configuration": "B"], xcconfig: AbsolutePath("/project/release.xcconfig"))
        )

        let target = Target.test(name: "name",
                                 platform: .iOS,
                                 product: .app,
                                 bundleId: "com.bundle.id",
                                 infoPlist: .file(path: AbsolutePath("/project/info.plist")),
                                 entitlements: AbsolutePath("/project/app.entitlements"),
                                 settings: settings,
                                 sources: [(path: AbsolutePath("/project/file.swift"), compilerFlags: nil)],
                                 resources: [
                                     .file(path: AbsolutePath("/project/image.png")),
                                     .folderReference(path: AbsolutePath("/project/reference")),
                                 ],
                                 coreDataModels: [CoreDataModel(path: AbsolutePath("/project/model.xcdatamodeld"),
                                                                versions: [AbsolutePath("/project/model.xcdatamodeld/1.xcdatamodel")],
                                                                currentVersion: "1")],
                                 headers: Headers(public: [AbsolutePath("/project/public.h")],
                                                  private: [AbsolutePath("/project/private.h")],
                                                  project: [AbsolutePath("/project/project.h")]),
                                 dependencies: [])

        // When
        let files = try subject.targetFiles(target: target)

        // Then
        XCTAssertTrue(files.isSuperset(of: [
            GroupFileElement(path: "/project/debug.xcconfig", group: target.filesGroup),
            GroupFileElement(path: "/project/release.xcconfig", group: target.filesGroup),
            GroupFileElement(path: "/project/file.swift", group: target.filesGroup),
            GroupFileElement(path: "/project/image.png", group: target.filesGroup),
            GroupFileElement(path: "/project/reference", group: target.filesGroup, isReference: true),
            GroupFileElement(path: "/project/public.h", group: target.filesGroup),
            GroupFileElement(path: "/project/project.h", group: target.filesGroup),
            GroupFileElement(path: "/project/private.h", group: target.filesGroup),
            GroupFileElement(path: "/project/model.xcdatamodeld/1.xcdatamodel", group: target.filesGroup),
            GroupFileElement(path: "/project/model.xcdatamodeld", group: target.filesGroup),
        ]))
    }

    func test_generateProduct() throws {
        // Given
        let pbxproj = PBXProj()
        let project = Project.test(targets: [
            .test(name: "App", product: .app),
            .test(name: "Framework", product: .framework),
            .test(name: "Library", product: .staticLibrary),
        ])
        let graph = Graph.test()
        let groups = ProjectGroups.generate(project: project,
                                            pbxproj: pbxproj,
                                            xcodeprojPath: project.path.appending(component: "\(project.fileName).xcodeproj"),
                                            sourceRootPath: project.path)

        // When
        try subject.generateProjectFiles(project: project,
                                         graph: graph,
                                         groups: groups,
                                         pbxproj: pbxproj,
                                         sourceRootPath: project.path)

        // Then
        XCTAssertEqual(groups.products.flattenedChildren, [
            "App.app",
            "Framework.framework",
            "libLibrary.a",
        ])
    }

    func test_generateProducts_stableOrder() throws {
        for _ in 0 ..< 5 {
            let pbxproj = PBXProj()
            let subject = ProjectFileElements()
            let targets: [Target] = [
                .test(name: "App1", product: .app),
                .test(name: "App2", product: .app),
                .test(name: "Framework1", product: .framework),
                .test(name: "Framework2", product: .framework),
                .test(name: "Library1", product: .staticLibrary),
                .test(name: "Library2", product: .staticLibrary),
            ].shuffled()

            let project = Project.test(targets: targets)
            let graph = Graph.test()
            let groups = ProjectGroups.generate(project: project,
                                                pbxproj: pbxproj,
                                                xcodeprojPath: project.path.appending(component: "\(project.fileName).xcodeproj"),
                                                sourceRootPath: project.path)

            // When
            try subject.generateProjectFiles(project: project,
                                             graph: graph,
                                             groups: groups,
                                             pbxproj: pbxproj,
                                             sourceRootPath: project.path)

            // Then
            XCTAssertEqual(groups.products.flattenedChildren, [
                "App1.app",
                "App2.app",
                "Framework1.framework",
                "Framework2.framework",
                "libLibrary1.a",
                "libLibrary2.a",
            ])
        }
    }

    func test_generateProduct_fileReferencesProperties() throws {
        // Given
        let pbxproj = PBXProj()
        let project = Project.test(targets: [
            .test(name: "App", product: .app),
        ])
        let graph = Graph.test()
        let groups = ProjectGroups.generate(project: project,
                                            pbxproj: pbxproj,
                                            xcodeprojPath: project.path.appending(component: "\(project.fileName).xcodeproj"),
                                            sourceRootPath: project.path)

        // When
        try subject.generateProjectFiles(project: project,
                                         graph: graph,
                                         groups: groups,
                                         pbxproj: pbxproj,
                                         sourceRootPath: project.path)

        // Then
        let fileReference = subject.product(target: "App")
        XCTAssertEqual(fileReference?.sourceTree, .buildProductsDir)
    }

    func test_generateDependencies_whenPrecompiledNode() throws {
        let pbxproj = PBXProj()
        let sourceRootPath = AbsolutePath("/")
        let target = Target.test()
        let projectGroupName = "Project"
        let projectGroup: ProjectGroup = .group(name: projectGroupName)
        let project = Project.test(path: AbsolutePath("/"), filesGroup: projectGroup, targets: [target])
        let groups = ProjectGroups.generate(project: project,
                                            pbxproj: pbxproj,
                                            xcodeprojPath: project.path.appending(component: "\(project.fileName).xcodeproj"),
                                            sourceRootPath: sourceRootPath)
        var dependencies: Set<GraphDependencyReference> = Set()
        let precompiledNode = GraphDependencyReference.testFramework(path: project.path.appending(component: "waka.framework"))
        dependencies.insert(precompiledNode)

        try subject.generate(dependencyReferences: dependencies,
                             groups: groups,
                             pbxproj: pbxproj,
                             sourceRootPath: sourceRootPath,
                             filesGroup: project.filesGroup)

        let fileReference = groups.sortedMain.group(named: projectGroupName)?.children.first as? PBXFileReference
        XCTAssertEqual(fileReference?.path, "waka.framework")
        XCTAssertEqual(fileReference?.path, "waka.framework")
        XCTAssertNil(fileReference?.name)
    }

    func test_generatePath_whenGroupIsSpecified() throws {
        // Given
        let pbxproj = PBXProj()
        let path = AbsolutePath("/a/b/c/file.swift")
        let fileElement = GroupFileElement(path: path, group: .group(name: "SomeGroup"))
        let project = Project.test(filesGroup: .group(name: "SomeGroup"))
        let sourceRootPath = AbsolutePath("/a/project/")
        let groups = ProjectGroups.generate(project: project,
                                            pbxproj: pbxproj,
                                            xcodeprojPath: project.path.appending(component: "\(project.fileName).xcodeproj"),
                                            sourceRootPath: sourceRootPath)

        // When
        try subject.generate(fileElement: fileElement,
                             groups: groups,
                             pbxproj: pbxproj,
                             sourceRootPath: sourceRootPath)

        // Then
        let group = groups.sortedMain.group(named: "SomeGroup")

        let bGroup: PBXGroup = group?.children.first! as! PBXGroup
        XCTAssertEqual(bGroup.name, "b")
        XCTAssertEqual(bGroup.path, "../b")
        XCTAssertEqual(bGroup.sourceTree, .group)

        let cGroup: PBXGroup = bGroup.children.first! as! PBXGroup
        XCTAssertEqual(cGroup.path, "c")
        XCTAssertNil(cGroup.name)
        XCTAssertEqual(cGroup.sourceTree, .group)

        let file: PBXFileReference = cGroup.children.first! as! PBXFileReference
        XCTAssertEqual(file.path, "file.swift")
        XCTAssertNil(file.name)
        XCTAssertEqual(file.sourceTree, .group)
    }

    func test_addLocalizedFile() throws {
        // Given
        let pbxproj = PBXProj()
        let group = PBXGroup()
        let file: AbsolutePath = "/path/to/resources/en.lproj/App.strings"

        // When
        subject.addLocalizedFile(localizedFile: file,
                                 toGroup: group,
                                 pbxproj: pbxproj)

        // Then
        let variantGroup = group.children.first as? PBXVariantGroup
        XCTAssertEqual(variantGroup?.name, "App.strings")
        XCTAssertNil(variantGroup?.path)
        XCTAssertEqual(variantGroup?.children.map { $0.name }, ["en"])
        XCTAssertEqual(variantGroup?.children.map { $0.path }, ["en.lproj/App.strings"])
        XCTAssertEqual(variantGroup?.children.map { ($0 as? PBXFileReference)?.lastKnownFileType }, [
            Xcode.filetype(extension: "strings"),
        ])
    }

    func test_addVersionGroupElement() throws {
        let from = AbsolutePath("/project/")
        let folderAbsolutePath = AbsolutePath("/project/model.xcdatamodel")
        let folderRelativePath = RelativePath("./model.xcdatamodel")
        let group = PBXGroup()
        let pbxproj = PBXProj()
        pbxproj.add(object: group)
        _ = subject.addVersionGroupElement(from: from,
                                           folderAbsolutePath: folderAbsolutePath,
                                           folderRelativePath: folderRelativePath,
                                           name: nil,
                                           toGroup: group,
                                           pbxproj: pbxproj)
        let versionGroup: XCVersionGroup? = group.children.first as? XCVersionGroup
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
        let pbxproj = PBXProj()
        pbxproj.add(object: group)
        _ = subject.addFileElement(from: from,
                                   fileAbsolutePath: fileAbsolutePath,
                                   fileRelativePath: fileRelativePath,
                                   name: nil,
                                   toGroup: group,
                                   pbxproj: pbxproj)
        let file: PBXFileReference? = group.children.first as? PBXFileReference
        XCTAssertEqual(file?.path, "file.swift")
        XCTAssertEqual(file?.sourceTree, .group)
        XCTAssertNil(file?.name)
        XCTAssertEqual(file?.lastKnownFileType, Xcode.filetype(extension: "swift"))
    }

    func test_generatePlaygrounds() throws {
        let pbxproj = PBXProj()
        let temporaryPath = try self.temporaryPath()

        let playgroundsPath = temporaryPath.appending(component: "Playgrounds")
        let playgroundPath = playgroundsPath.appending(component: "Test.playground")

        playgrounds.pathsStub = { projectPath in
            if projectPath == temporaryPath {
                return [playgroundPath]
            } else {
                return []
            }
        }

        let project = Project.test(path: temporaryPath)
        let groups = ProjectGroups.generate(project: project,
                                            pbxproj: pbxproj,
                                            xcodeprojPath: project.path.appending(component: "\(project.fileName).xcodeproj"),
                                            sourceRootPath: temporaryPath,
                                            playgrounds: playgrounds)

        subject.generatePlaygrounds(path: temporaryPath,
                                    groups: groups,
                                    pbxproj: pbxproj,
                                    sourceRootPath: temporaryPath)
        let file: PBXFileReference? = groups.playgrounds?.children.first as? PBXFileReference

        XCTAssertEqual(file?.sourceTree, .group)
        XCTAssertEqual(file?.lastKnownFileType, "file.playground")
        XCTAssertEqual(file?.path, "Test.playground")
        XCTAssertNil(file?.name)
        XCTAssertEqual(file?.xcLanguageSpecificationIdentifier, "xcode.lang.swift")
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

    func test_generateDependencies_sdks() throws {
        // Given
        let pbxproj = PBXProj()
        let project = Project.test()
        let sourceRootPath = AbsolutePath("/a/project/")
        let groups = ProjectGroups.generate(project: project,
                                            pbxproj: pbxproj,
                                            xcodeprojPath: project.path.appending(component: "\(project.fileName).xcodeproj"),
                                            sourceRootPath: sourceRootPath)

        let sdk = try SDKNode(name: "ARKit.framework",
                              platform: .iOS,
                              status: .required,
                              source: .developer)
        let sdkDependency = GraphDependencyReference.sdk(path: sdk.path, status: sdk.status, source: .developer)

        // When
        try subject.generate(dependencyReferences: [sdkDependency],
                             groups: groups, pbxproj: pbxproj,
                             sourceRootPath: sourceRootPath,
                             filesGroup: .group(name: "Project"))

        // Then
        XCTAssertEqual(groups.frameworks.flattenedChildren, [
            "ARKit.framework",
        ])

        let sdkElement = subject.sdks[sdk.path]
        XCTAssertNotNil(sdkElement)
        XCTAssertEqual(sdkElement?.sourceTree, .developerDir)
        XCTAssertEqual(sdkElement?.path, sdk.path.relative(to: "/").pathString)
        XCTAssertEqual(sdkElement?.name, sdk.path.basename)
    }

    func test_generateDependencies_remoteSwiftPackage_doNotGenerateElements() throws {
        // Given
        let pbxproj = PBXProj()
        let target = Target.empty(name: "TargetA")
        let project = Project.empty(path: "/a/project",
                                    targets: [target],
                                    packages: [.remote(url: "url", requirement: .branch("master"))])
        let groups = ProjectGroups.generate(project: .test(),
                                            pbxproj: pbxproj,
                                            xcodeprojPath: project.path.appending(component: "\(project.fileName).xcodeproj"),
                                            sourceRootPath: project.path)

        let package = PackageProductNode(product: "A", path: "/packages/url")

        let graph = createGraph(project: project, target: target, dependencies: [package])

        // When
        try subject.generateProjectFiles(project: project,
                                         graph: graph,
                                         groups: groups,
                                         pbxproj: pbxproj,
                                         sourceRootPath: project.path)

        // Then
        let projectGroup = groups.sortedMain.group(named: "Project")
        XCTAssertEqual(projectGroup?.flattenedChildren, [])
    }

    // MARK: -

    private func createGraph(project: Project, target: Target, dependencies: [GraphNode]) -> Graph {
        let targetNode = TargetNode(project: project, target: target, dependencies: dependencies)
        return Graph.test(projects: [project], targets: [project.path: [targetNode]])
    }
}

private extension PBXGroup {
    /// Retuns all the child variant groups (recursively)
    var debugVariantGroupPaths: [String] {
        children.flatMap { (element: PBXFileElement) -> [String] in
            switch element {
            case let group as PBXVariantGroup:
                return [group.nameOrPath]
            case let group as PBXGroup:
                return group.debugVariantGroupPaths.map { group.nameOrPath + "/" + $0 }
            default:
                return []
            }
        }
    }
}
