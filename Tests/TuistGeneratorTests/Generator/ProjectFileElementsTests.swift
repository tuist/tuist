import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class ProjectFileElementsTests: TuistUnitTestCase {
    var subject: ProjectFileElements!
    var groups: ProjectGroups!
    var pbxproj: PBXProj!

    override func setUp() {
        super.setUp()
        pbxproj = PBXProj()
        groups = ProjectGroups.generate(
            project: .test(path: "/path", sourceRootPath: "/path", xcodeProjPath: "/path/Project.xcodeproj"),
            pbxproj: pbxproj
        )

        subject = ProjectFileElements()
    }

    override func tearDown() {
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
                .debug: Configuration(xcconfig: try! AbsolutePath(validating: "/project/debug.xcconfig")),
                .release: Configuration(xcconfig: try! AbsolutePath(validating: "/project/release.xcconfig")),
            ]
        )

        let project = Project.test(
            path: try! AbsolutePath(validating: "/project/"),
            settings: settings,
            schemes: [
                .test(
                    runAction: .test(
                        options: .init(storeKitConfigurationPath: "/path/to/configuration.storekit")
                    )
                ),
            ],
            additionalFiles: [
                .file(path: "/path/to/file"),
                .folderReference(path: "/path/to/folder"),
            ]
        )

        // When
        let files = subject.projectFiles(project: project)

        // Then
        XCTAssertTrue(files.isSuperset(of: [
            GroupFileElement(path: "/project/debug.xcconfig", group: project.filesGroup),
            GroupFileElement(path: "/project/release.xcconfig", group: project.filesGroup),
            GroupFileElement(path: "/path/to/file", group: project.filesGroup),
            GroupFileElement(path: "/path/to/folder", group: project.filesGroup, isReference: true),
            GroupFileElement(path: "/path/to/configuration.storekit", group: project.filesGroup),
        ]))
    }

    func test_addElement() throws {
        // Given
        let element = GroupFileElement(
            path: "/path/myfolder/resources/a.png",
            group: .group(name: "Project")
        )

        // When
        try subject.generate(
            fileElement: element,
            groups: groups,
            pbxproj: pbxproj,
            sourceRootPath: "/path"
        )

        // Then
        let projectGroup = groups.sortedMain.group(named: "Project")
        XCTAssertEqual(projectGroup?.flattenedChildren, [
            "myfolder/resources/a.png",
        ])
    }

    func test_addElement_withDotFolders() throws {
        // Given
        let element = GroupFileElement(
            path: "/path/my.folder/resources/a.png",
            group: .group(name: "Project")
        )

        // When
        try subject.generate(
            fileElement: element,
            groups: groups,
            pbxproj: pbxproj,
            sourceRootPath: "/path"
        )

        // Then
        let projectGroup = groups.sortedMain.group(named: "Project")
        XCTAssertEqual(projectGroup?.flattenedChildren, [
            "my.folder/resources/a.png",
        ])
    }

    func test_addElement_fileReference() throws {
        // Given
        let element = GroupFileElement(
            path: "/path/myfolder/resources/generated_images",
            group: .group(name: "Project"),
            isReference: true
        )

        // When
        try subject.generate(
            fileElement: element,
            groups: groups,
            pbxproj: pbxproj,
            sourceRootPath: "/path"
        )

        // Then
        let projectGroup = groups.sortedMain.group(named: "Project")
        XCTAssertEqual(projectGroup?.flattenedChildren, [
            "myfolder/resources/generated_images",
        ])
    }

    func test_addElement_parentDirectories() throws {
        // Given
        let element = GroupFileElement(
            path: "/path/another/path/resources/a.png",
            group: .group(name: "Project")
        )

        // When
        try subject.generate(
            fileElement: element,
            groups: groups,
            pbxproj: pbxproj,
            sourceRootPath: "/path/project"
        )

        // Then
        let projectGroup = groups.sortedMain.group(named: "Project")
        XCTAssertEqual(projectGroup?.flattenedChildren, [
            "another/path/resources/a.png",
        ])
    }

    func test_addElement_xcassets() throws {
        // Given
        let element = GroupFileElement(
            path: "/path/myfolder/resources/assets.xcassets",
            group: .group(name: "Project")
        )

        // When
        try subject.generate(
            fileElement: element,
            groups: groups,
            pbxproj: pbxproj,
            sourceRootPath: "/path"
        )

        // Then
        let projectGroup = groups.sortedMain.group(named: "Project")
        XCTAssertEqual(projectGroup?.flattenedChildren, [
            "myfolder/resources/assets.xcassets",
        ])
    }

    func test_addElement_docc() throws {
        // Given
        let element = GroupFileElement(
            path: "/path/myfolder/resources/ImportantDocumentation.docc",
            group: .group(name: "Project")
        )

        // When
        try subject.generate(
            fileElement: element,
            groups: groups,
            pbxproj: pbxproj,
            sourceRootPath: "/path"
        )

        // Then
        let projectGroup = groups.sortedMain.group(named: "Project")
        XCTAssertEqual(projectGroup?.flattenedChildren, [
            "myfolder/resources/ImportantDocumentation.docc",
        ])
    }

    func test_addElement_scnassets() throws {
        // Given
        let element = GroupFileElement(
            path: "/path/myfolder/resources/assets.scnassets",
            group: .group(name: "Project")
        )

        // When
        try subject.generate(
            fileElement: element,
            groups: groups,
            pbxproj: pbxproj,
            sourceRootPath: "/path"
        )

        // Then
        let projectGroup = groups.sortedMain.group(named: "Project")
        XCTAssertEqual(projectGroup?.flattenedChildren, [
            "myfolder/resources/assets.scnassets",
        ])
    }

    func test_addElement_lproj_multiple_files() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let resources = try createFiles([
            "resources/en.lproj/App.strings",
            "resources/en.lproj/App.stringsdict",
            "resources/en.lproj/Extension.strings",
            "resources/fr.lproj/App.strings",
            "resources/fr.lproj/App.stringsdict",
            "resources/fr.lproj/Extension.strings",
        ])

        let elements = resources.map {
            GroupFileElement(
                path: $0,
                group: .group(name: "Project"),
                isReference: true
            )
        }

        // When
        try elements.forEach {
            try subject.generate(
                fileElement: $0,
                groups: groups,
                pbxproj: pbxproj,
                sourceRootPath: temporaryPath
            )
        }

        // Then
        let projectGroup = groups.sortedMain.group(named: "Project")
        XCTAssertEqual(projectGroup?.flattenedChildren, [
            "resources/App.strings/en",
            "resources/App.strings/fr",
            "resources/App.stringsdict/en",
            "resources/App.stringsdict/fr",
            "resources/Extension.strings/en",
            "resources/Extension.strings/fr",
        ])

        XCTAssertEqual(projectGroup?.debugVariantGroupPaths, [
            "resources/App.strings",
            "resources/App.stringsdict",
            "resources/Extension.strings",
        ])
    }

    func test_addElement_lproj_variant_groups() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let resources = try createFiles([
            "resources/Base.lproj/Controller.xib",
            "resources/Base.lproj/Intents.intentdefinition",
            "resources/Base.lproj/Storyboard.storyboard",
            "resources/en.lproj/Controller.xib",
            "resources/en.lproj/Intents.strings",
            "resources/en.lproj/Storyboard.strings",
            "resources/fr.lproj/Controller.strings",
            "resources/fr.lproj/Intents.strings",
            "resources/fr.lproj/Storyboard.strings",
        ])

        let elements = resources.map {
            GroupFileElement(
                path: $0,
                group: .group(name: "Project"),
                isReference: true
            )
        }

        // When
        try elements.forEach {
            try subject.generate(
                fileElement: $0,
                groups: groups,
                pbxproj: pbxproj,
                sourceRootPath: temporaryPath
            )
        }

        // Then
        let projectGroup = groups.sortedMain.group(named: "Project")
        XCTAssertEqual(projectGroup?.flattenedChildren, [
            "resources/Controller.xib/Base",
            "resources/Controller.xib/en",
            "resources/Controller.xib/fr",
            "resources/Intents.intentdefinition/Base",
            "resources/Intents.intentdefinition/en",
            "resources/Intents.intentdefinition/fr",
            "resources/Storyboard.storyboard/Base",
            "resources/Storyboard.storyboard/en",
            "resources/Storyboard.storyboard/fr",
        ])

        XCTAssertEqual(projectGroup?.debugVariantGroupPaths, [
            "resources/Controller.xib",
            "resources/Intents.intentdefinition",
            "resources/Storyboard.storyboard",
        ])
    }

    func test_addElement_lproj_knownRegions() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let resources = try createFiles([
            "resources/en.lproj/App.strings",
            "resources/en.lproj/Extension.strings",
            "resources/fr.lproj/App.strings",
            "resources/fr.lproj/Extension.strings",
            "resources/Base.lproj/App.strings",
            "resources/Base.lproj/Extension.strings",
        ])

        let elements = resources.map {
            GroupFileElement(
                path: $0,
                group: .group(name: "Project"),
                isReference: true
            )
        }

        // When
        try elements.forEach {
            try subject.generate(
                fileElement: $0,
                groups: groups,
                pbxproj: pbxproj,
                sourceRootPath: temporaryPath
            )
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
            debug: Configuration(
                settings: ["Configuration": "A"],
                xcconfig: try AbsolutePath(validating: "/project/debug.xcconfig")
            ),
            release: Configuration(
                settings: ["Configuration": "B"],
                xcconfig: try AbsolutePath(validating: "/project/release.xcconfig")
            )
        )

        let target = Target.test(
            name: "name",
            platform: .iOS,
            product: .app,
            bundleId: "com.bundle.id",
            infoPlist: .file(path: try AbsolutePath(validating: "/project/info.plist")),
            entitlements: try AbsolutePath(validating: "/project/app.entitlements"),
            settings: settings,
            sources: [SourceFile(path: try AbsolutePath(validating: "/project/file.swift"))],
            resources: [
                .file(path: try AbsolutePath(validating: "/project/image.png")),
                .folderReference(path: try AbsolutePath(validating: "/project/reference")),
            ],
            copyFiles: [
                CopyFilesAction(
                    name: "Copy Templates",
                    destination: .sharedSupport,
                    subpath: "Templates",
                    files: [
                        .file(path: "/project/tuist.rtfd"),
                        .file(path: "/project/tuist.rtfd/TXT.rtf"),
                    ]
                ),
            ],
            coreDataModels: [CoreDataModel(
                path: try AbsolutePath(validating: "/project/model.xcdatamodeld"),
                versions: [try AbsolutePath(validating: "/project/model.xcdatamodeld/1.xcdatamodel")],
                currentVersion: "1"
            )],
            headers: Headers(
                public: [try AbsolutePath(validating: "/project/public.h")],
                private: [try AbsolutePath(validating: "/project/private.h")],
                project: [try AbsolutePath(validating: "/project/project.h")]
            ),
            dependencies: [],
            playgrounds: ["/project/MyPlayground.playground"],
            additionalFiles: [.file(path: try AbsolutePath(validating: "/project/README.md"))]
        )

        // When
        let files = try subject.targetFiles(target: target)

        // Then
        XCTAssertTrue(files.isSuperset(of: [
            GroupFileElement(path: "/project/debug.xcconfig", group: target.filesGroup),
            GroupFileElement(path: "/project/release.xcconfig", group: target.filesGroup),
            GroupFileElement(path: "/project/file.swift", group: target.filesGroup),
            GroupFileElement(path: "/project/MyPlayground.playground", group: target.filesGroup),
            GroupFileElement(path: "/project/image.png", group: target.filesGroup),
            GroupFileElement(path: "/project/reference", group: target.filesGroup, isReference: true),
            GroupFileElement(path: "/project/public.h", group: target.filesGroup),
            GroupFileElement(path: "/project/project.h", group: target.filesGroup),
            GroupFileElement(path: "/project/private.h", group: target.filesGroup),
            GroupFileElement(path: "/project/model.xcdatamodeld/1.xcdatamodel", group: target.filesGroup),
            GroupFileElement(path: "/project/model.xcdatamodeld", group: target.filesGroup),
            GroupFileElement(path: "/project/tuist.rtfd", group: target.filesGroup),
            GroupFileElement(path: "/project/tuist.rtfd/TXT.rtf", group: target.filesGroup),
            GroupFileElement(path: "/project/README.md", group: target.filesGroup),
        ]))
    }

    func test_generateProduct() throws {
        // Given
        let pbxproj = PBXProj()
        let project = Project.test(
            path: .root,
            sourceRootPath: .root,
            xcodeProjPath: AbsolutePath.root.appending(component: "Project.xcodeproj"),
            targets: [
                .test(name: "App", product: .app),
                .test(name: "Framework", product: .framework),
                .test(name: "Library", product: .staticLibrary),
            ]
        )
        let graph = Graph.test()
        let graphTraverser = GraphTraverser(graph: graph)
        let groups = ProjectGroups.generate(project: project, pbxproj: pbxproj)

        // When
        try subject.generateProjectFiles(
            project: project,
            graphTraverser: graphTraverser,
            groups: groups,
            pbxproj: pbxproj
        )

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

            let project = Project.test(
                path: .root,
                sourceRootPath: .root,
                xcodeProjPath: AbsolutePath.root.appending(component: "Project.xcodeproj"),
                targets: targets
            )
            let graph = Graph.test()
            let graphTraverser = GraphTraverser(graph: graph)
            let groups = ProjectGroups.generate(project: project, pbxproj: pbxproj)

            // When
            try subject.generateProjectFiles(
                project: project,
                graphTraverser: graphTraverser,
                groups: groups,
                pbxproj: pbxproj
            )

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
        let project = Project.test(
            path: .root,
            sourceRootPath: .root,
            xcodeProjPath: AbsolutePath.root.appending(component: "Project.xcodeproj"),
            targets: [
                .test(name: "App", product: .app),
            ]
        )
        let graph = Graph.test()
        let graphTraverser = GraphTraverser(graph: graph)
        let groups = ProjectGroups.generate(project: project, pbxproj: pbxproj)

        // When
        try subject.generateProjectFiles(
            project: project,
            graphTraverser: graphTraverser,
            groups: groups,
            pbxproj: pbxproj
        )

        // Then
        let fileReference = subject.product(target: "App")
        XCTAssertEqual(fileReference?.sourceTree, .buildProductsDir)
    }

    func test_generateDependencies_whenPrecompiledNode() throws {
        let pbxproj = PBXProj()
        let sourceRootPath = try AbsolutePath(validating: "/")
        let target = Target.test()
        let projectGroupName = "Project"
        let projectGroup: ProjectGroup = .group(name: projectGroupName)
        let project = Project.test(
            path: .root,
            sourceRootPath: .root,
            xcodeProjPath: AbsolutePath.root.appending(component: "Project.xcodeproj"),
            filesGroup: projectGroup,
            targets: [target]
        )
        let groups = ProjectGroups.generate(project: project, pbxproj: pbxproj)
        var dependencies: Set<GraphDependencyReference> = Set()
        let precompiledNode = GraphDependencyReference.testFramework(path: project.path.appending(component: "waka.framework"))
        dependencies.insert(precompiledNode)

        try subject.generate(
            dependencyReferences: dependencies,
            groups: groups,
            pbxproj: pbxproj,
            sourceRootPath: sourceRootPath,
            filesGroup: project.filesGroup
        )

        let fileReference = groups.sortedMain.group(named: projectGroupName)?.children.first as? PBXFileReference
        XCTAssertEqual(fileReference?.path, "waka.framework")
        XCTAssertEqual(fileReference?.path, "waka.framework")
        XCTAssertNil(fileReference?.name)
    }

    func test_generatePath_whenGroupIsSpecified() throws {
        // Given
        let pbxproj = PBXProj()
        let path = try AbsolutePath(validating: "/a/b/c/file.swift")
        let fileElement = GroupFileElement(path: path, group: .group(name: "SomeGroup"))
        let project = Project.test(
            path: .root,
            sourceRootPath: .root,
            xcodeProjPath: AbsolutePath.root.appending(component: "Project.xcodeproj"),
            filesGroup: .group(name: "SomeGroup")
        )
        let sourceRootPath = try AbsolutePath(validating: "/a/project/")
        let groups = ProjectGroups.generate(project: project, pbxproj: pbxproj)

        // When
        try subject.generate(
            fileElement: fileElement,
            groups: groups,
            pbxproj: pbxproj,
            sourceRootPath: sourceRootPath
        )

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
        subject.addLocalizedFile(
            localizedFile: file,
            toGroup: group,
            pbxproj: pbxproj
        )

        // Then
        let variantGroup = group.children.first as? PBXVariantGroup
        XCTAssertEqual(variantGroup?.name, "App.strings")
        XCTAssertNil(variantGroup?.path)
        XCTAssertEqual(variantGroup?.children.map(\.name), ["en"])
        XCTAssertEqual(variantGroup?.children.map(\.path), ["en.lproj/App.strings"])
        XCTAssertEqual(variantGroup?.children.map { ($0 as? PBXFileReference)?.lastKnownFileType }, [
            Xcode.filetype(extension: "strings"),
        ])
    }

    func test_addPlayground() throws {
        // Given
        let from = try AbsolutePath(validating: "/project/")
        let fileAbsolutePath = try AbsolutePath(validating: "/project/MyPlayground.playground")
        let fileRelativePath = RelativePath("./MyPlayground.playground")
        let group = PBXGroup()
        let pbxproj = PBXProj()
        pbxproj.add(object: group)

        // When
        subject.addFileElement(
            from: from,
            fileAbsolutePath: fileAbsolutePath,
            fileRelativePath: fileRelativePath,
            name: nil,
            toGroup: group,
            pbxproj: pbxproj
        )

        // Then
        let file: PBXFileReference? = group.children.first as? PBXFileReference
        XCTAssertEqual(file?.path, "MyPlayground.playground")
        XCTAssertEqual(file?.sourceTree, .group)
        XCTAssertNil(file?.name)
        XCTAssertEqual(file?.lastKnownFileType, Xcode.filetype(extension: fileAbsolutePath.extension!))
    }

    func test_addVersionGroupElement() throws {
        // Given
        let from = try AbsolutePath(validating: "/project/")
        let folderAbsolutePath = try AbsolutePath(validating: "/project/model.xcdatamodeld")
        let folderRelativePath = RelativePath("./model.xcdatamodeld")
        let group = PBXGroup()
        let pbxproj = PBXProj()
        pbxproj.add(object: group)

        // When
        _ = subject.addVersionGroupElement(
            from: from,
            folderAbsolutePath: folderAbsolutePath,
            folderRelativePath: folderRelativePath,
            name: nil,
            toGroup: group,
            pbxproj: pbxproj
        )

        // Then
        let versionGroup = try XCTUnwrap(group.children.first as? XCVersionGroup)
        XCTAssertEqual(versionGroup.path, "model.xcdatamodeld")
        XCTAssertEqual(versionGroup.sourceTree, .group)
        XCTAssertNil(versionGroup.name)
        XCTAssertEqual(versionGroup.versionGroupType, "wrapper.xcdatamodel")
    }

    func test_addFileElement() throws {
        let from = try AbsolutePath(validating: "/project/")
        let fileAbsolutePath = try AbsolutePath(validating: "/project/file.swift")
        let fileRelativePath = RelativePath("./file.swift")
        let group = PBXGroup()
        let pbxproj = PBXProj()
        pbxproj.add(object: group)
        subject.addFileElement(
            from: from,
            fileAbsolutePath: fileAbsolutePath,
            fileRelativePath: fileRelativePath,
            name: nil,
            toGroup: group,
            pbxproj: pbxproj
        )
        let file: PBXFileReference? = group.children.first as? PBXFileReference
        XCTAssertEqual(file?.path, "file.swift")
        XCTAssertEqual(file?.sourceTree, .group)
        XCTAssertNil(file?.name)
        XCTAssertEqual(file?.lastKnownFileType, Xcode.filetype(extension: "swift"))
    }

    func test_group() {
        let group = PBXGroup()
        let path = try! AbsolutePath(validating: "/path/to/folder")
        subject.elements[path] = group
        XCTAssertEqual(subject.group(path: path), group)
    }

    func test_file() {
        let file = PBXFileReference()
        let path = try! AbsolutePath(validating: "/path/to/folder")
        subject.elements[path] = file
        XCTAssertEqual(subject.file(path: path), file)
    }

    func test_isLocalized() {
        let path = try! AbsolutePath(validating: "/path/to/es.lproj")
        XCTAssertTrue(subject.isLocalized(path: path))
    }

    func test_isVersionGroup() {
        let path = try! AbsolutePath(validating: "/path/to/model.xcdatamodeld")
        XCTAssertTrue(subject.isVersionGroup(path: path))
    }

    func test_normalize_whenLocalized() {
        let path = try! AbsolutePath(validating: "/test/es.lproj/Main.storyboard")
        let normalized = subject.normalize(path)
        XCTAssertEqual(normalized, try AbsolutePath(validating: "/test/es.lproj"))
    }

    func test_normalize() {
        let path = try! AbsolutePath(validating: "/test/file.swift")
        let normalized = subject.normalize(path)
        XCTAssertEqual(normalized, path)
    }

    func test_closestRelativeElementPath() {
        let pathRelativeToSourceRoot = try! AbsolutePath(validating: "/a/framework/framework.framework")
            .relative(to: try! AbsolutePath(validating: "/a/b/c/project"))
        let got = subject.closestRelativeElementPath(pathRelativeToSourceRoot: pathRelativeToSourceRoot)
        XCTAssertEqual(got, RelativePath("../../../framework"))
    }

    func test_generateDependencies_sdks() throws {
        // Given
        let pbxproj = PBXProj()
        let sourceRootPath = try AbsolutePath(validating: "/a/project/")
        let project = Project.test(
            path: sourceRootPath,
            sourceRootPath: sourceRootPath,
            xcodeProjPath: sourceRootPath.appending(component: "Project.xcodeproj")
        )
        let groups = ProjectGroups.generate(project: project, pbxproj: pbxproj)

        let sdkPath = try temporaryPath().appending(component: "ARKit.framework")
        let sdkStatus: SDKStatus = .required
        let sdkSource: SDKSource = .developer
        let sdkDependency = GraphDependencyReference.sdk(path: sdkPath, status: sdkStatus, source: sdkSource)

        // When
        try subject.generate(
            dependencyReferences: [sdkDependency],
            groups: groups,
            pbxproj: pbxproj,
            sourceRootPath: sourceRootPath,
            filesGroup: .group(name: "Project")
        )

        // Then
        XCTAssertEqual(groups.frameworks.flattenedChildren, [
            "ARKit.framework",
        ])

        let sdkElement = subject.sdks[sdkPath]
        XCTAssertNotNil(sdkElement)
        XCTAssertEqual(sdkElement?.sourceTree, .developerDir)
        XCTAssertEqual(sdkElement?.path, sdkPath.relative(to: "/").pathString)
        XCTAssertEqual(sdkElement?.name, sdkPath.basename)
    }

    func test_generateDependencies_remoteSwiftPackage_doNotGenerateElements() throws {
        // Given
        let pbxproj = PBXProj()
        let target = Target.empty(name: "TargetA")
        let project = Project.empty(
            path: "/a/project",
            targets: [target],
            packages: [.remote(url: "url", requirement: .branch("master"))]
        )
        let graphTarget: GraphTarget = .test(path: project.path, target: target, project: project)
        let groups = ProjectGroups.generate(
            project: .test(
                path: .root,
                sourceRootPath: .root,
                xcodeProjPath: AbsolutePath.root.appending(component: "Project.xcodeproj")
            ),
            pbxproj: pbxproj
        )

        let graph = Graph.test(
            projects: [project.path: project],
            packages: [
                project.path: [
                    "A": .remote(url: "url", requirement: .branch("master")),
                ],
            ],
            targets: [
                graphTarget.path: [
                    graphTarget.target.name: graphTarget.target,
                ],
            ],
            dependencies: [
                .target(name: graphTarget.target.name, path: graphTarget.path): [
                    .packageProduct(path: project.path, product: "A"),
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateProjectFiles(
            project: project,
            graphTraverser: graphTraverser,
            groups: groups,
            pbxproj: pbxproj
        )

        // Then
        let projectGroup = groups.sortedMain.group(named: "Project")
        XCTAssertEqual(projectGroup?.flattenedChildren, [])
    }
}

extension PBXGroup {
    /// Retuns all the child variant groups (recursively)
    fileprivate var debugVariantGroupPaths: [String] {
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
