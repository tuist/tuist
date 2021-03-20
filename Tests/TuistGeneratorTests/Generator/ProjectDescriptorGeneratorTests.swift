import Foundation
import TSCBasic
import struct TSCUtility.Version
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class ProjectDescriptorGeneratorTests: TuistUnitTestCase {
    var subject: ProjectDescriptorGenerator!

    override func setUp() {
        super.setUp()
        system.swiftVersionStub = { "5.2" }
        subject = ProjectDescriptorGenerator()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_generate_testTargetIdentity() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let app = Target.test(
            name: "App",
            platform: .iOS,
            product: .app
        )
        let test = Target.test(
            name: "Tests",
            platform: .iOS,
            product: .unitTests
        )
        let project = Project.test(
            path: temporaryPath,
            sourceRootPath: temporaryPath,
            name: "Project",
            targets: [app, test]
        )

        let testGraphTarget = ValueGraphTarget(
            path: project.path,
            target: test,
            project: project
        )
        let appGraphTarget = ValueGraphTarget(path: project.path, target: app, project: project)

        let graph = ValueGraph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    testGraphTarget.target.name: testGraphTarget.target,
                    appGraphTarget.target.name: appGraphTarget.target,
                ],
            ],
            dependencies: [
                .target(name: testGraphTarget.target.name, path: testGraphTarget.path): [
                    .target(name: appGraphTarget.target.name, path: appGraphTarget.path),
                ],
            ]
        )
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let generatedProject = try subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxproj = generatedProject.xcodeProj.pbxproj
        let pbxproject = try pbxproj.rootProject()
        let nativeTargets = pbxproj.nativeTargets
        let attributes = pbxproject?.targetAttributes ?? [:]
        let appTarget = nativeTargets.first(where: { $0.name == "App" })
        XCTAssertTrue(attributes.contains { attribute in

            guard let testTargetID = attribute.value["TestTargetID"] as? PBXNativeTarget else {
                return false
            }

            return attribute.key.name == "Tests" && testTargetID == appTarget

        }, "Test target is missing from target attributes.")
    }

    func test_objectVersion_when_xcode11_and_spm() throws {
        xcodeController.selectedVersionStub = .success(Version(11, 0, 0))

        // Given
        let temporaryPath = try self.temporaryPath()
        let project = Project.test(
            path: temporaryPath,
            name: "Project",
            targets: [.test(dependencies: [.package(product: "A")])],
            packages: [.remote(url: "A", requirement: .exact("0.1"))]
        )

        let target = Target.test()
        let graphTarget = ValueGraphTarget.test(path: project.path, target: target, project: project)
        let graph = ValueGraph.test(
            projects: [project.path: project],
            packages: [
                project.path: [
                    "A": .remote(url: "A", requirement: .exact("0.1")),
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
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let got = try subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxproj = got.xcodeProj.pbxproj
        XCTAssertEqual(pbxproj.objectVersion, 52)
        XCTAssertEqual(pbxproj.archiveVersion, Xcode.LastKnown.archiveVersion)
    }

    func test_objectVersion_when_xcode11() throws {
        xcodeController.selectedVersionStub = .success(Version(11, 0, 0))

        // Given
        let temporaryPath = try self.temporaryPath()
        let project = Project.test(
            path: temporaryPath,
            name: "Project",
            targets: []
        )
        let graph = ValueGraph.test(
            projects: [project.path: project]
        )
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let got = try subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxproj = got.xcodeProj.pbxproj
        XCTAssertEqual(pbxproj.objectVersion, 50)
        XCTAssertEqual(pbxproj.archiveVersion, Xcode.LastKnown.archiveVersion)
    }

    func test_objectVersion_when_xcode10() throws {
        xcodeController.selectedVersionStub = .success(Version(10, 2, 1))

        // Given
        let temporaryPath = try self.temporaryPath()
        let project = Project.test(
            path: temporaryPath,
            name: "Project",
            targets: []
        )
        let graph = ValueGraph.test(
            projects: [project.path: project]
        )
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let got = try subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxproj = got.xcodeProj.pbxproj
        XCTAssertEqual(pbxproj.objectVersion, 50)
        XCTAssertEqual(pbxproj.archiveVersion, Xcode.LastKnown.archiveVersion)
    }

    func test_knownRegions() throws {
        // Given
        let path = try temporaryPath()
        let graph = ValueGraph.test(path: path)
        let graphTraverser = ValueGraphTraverser(graph: graph)
        let resources = [
            "resources/en.lproj/App.strings",
            "resources/en.lproj/Extension.strings",
            "resources/fr.lproj/App.strings",
            "resources/fr.lproj/Extension.strings",
            "resources/Base.lproj/App.strings",
            "resources/Base.lproj/Extension.strings",
        ]
        let project = Project.test(
            path: path,
            targets: [
                .test(resources: resources.map {
                    .file(path: path.appending(RelativePath($0)))
                }),
            ]
        )

        // When
        let got = try subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxProject = try XCTUnwrap(try got.xcodeProj.pbxproj.rootProject())
        XCTAssertEqual(pbxProject.knownRegions, [
            "Base",
            "en",
            "fr",
        ])
    }

    func test_generate_setsDefaultKnownRegions() throws {
        // Given
        let path = try temporaryPath()
        let graph = ValueGraph.test(path: path)
        let graphTraverser = ValueGraphTraverser(graph: graph)
        let project = Project.test(
            path: path,
            targets: []
        )

        // When
        let got = try subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxProject = try XCTUnwrap(try got.xcodeProj.pbxproj.rootProject())
        XCTAssertEqual(pbxProject.knownRegions, [
            "Base",
            "en",
        ])
    }

    func test_generate_setsOrganizationName() throws {
        // Given
        let path = try temporaryPath()
        let graph = ValueGraph.test(path: path)
        let graphTraverser = ValueGraphTraverser(graph: graph)
        let project = Project.test(
            path: path,
            organizationName: "tuist",
            targets: []
        )

        // When
        let got = try subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxProject = try XCTUnwrap(try got.xcodeProj.pbxproj.rootProject())
        let attributes = try XCTUnwrap(pbxProject.attributes as? [String: String])
        XCTAssertEqual(attributes, [
            "ORGANIZATIONNAME": "tuist",
        ])
    }

    func test_generate_setsResourcesTagsName() throws {
        // Given
        let path = try temporaryPath()
        let graph = ValueGraph.test(path: path)
        let graphTraverser = ValueGraphTraverser(graph: graph)
        let resources: [ResourceFileElement] = [.file(path: "/", tags: ["fileTag", "commonTag"]),
                                                .folderReference(path: "/", tags: ["folderTag", "commonTag"])]
        let project = Project.test(
            path: path,
            targets: [.test(resources: resources)]
        )

        // When
        let got = try subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxProject = try XCTUnwrap(try got.xcodeProj.pbxproj.rootProject())
        let attributes = try XCTUnwrap(pbxProject.attributes as? [String: AnyHashable])
        XCTAssertEqual(attributes, [
            "KnownAssetTags": ["fileTag", "folderTag", "commonTag"].sorted(),
        ])
    }

    func test_generate_setsDefaultDevelopmentRegion() throws {
        // Given
        let path = try temporaryPath()
        let graph = ValueGraph.test(path: path)
        let graphTraverser = ValueGraphTraverser(graph: graph)
        let project = Project.test(
            path: path,
            targets: []
        )

        // When
        let got = try subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxProject = try XCTUnwrap(try got.xcodeProj.pbxproj.rootProject())
        XCTAssertEqual(pbxProject.developmentRegion, "en")
    }

    func test_generate_setsDevelopmentRegion() throws {
        // Given
        let path = try temporaryPath()
        let graph = ValueGraph.test(path: path)
        let graphTraverser = ValueGraphTraverser(graph: graph)
        let project = Project.test(
            path: path,
            developmentRegion: "de",
            targets: []
        )

        // When
        let got = try subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxProject = try XCTUnwrap(try got.xcodeProj.pbxproj.rootProject())
        XCTAssertEqual(pbxProject.developmentRegion, "de")
    }

    func test_generate_localSwiftPackagePaths() throws {
        // Given
        let projectPath = AbsolutePath("/Project")
        let localPackagePath = AbsolutePath("/Packages/LocalPackageA")
        let project = Project.test(
            path: projectPath,
            sourceRootPath: projectPath,
            name: "Project",
            targets: [.test(dependencies: [.package(product: "A")])],
            packages: [.local(path: localPackagePath)]
        )

        let target = Target.test()
        let graphTarget = ValueGraphTarget(path: project.path, target: target, project: project)
        let graph = ValueGraph.test(
            projects: [project.path: project],
            packages: [
                project.path: [
                    "A": .local(path: localPackagePath),
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
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let got = try subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxproj = got.xcodeProj.pbxproj
        let rootGroup = try XCTUnwrap(pbxproj.rootGroup())
        let paths = rootGroup.children.compactMap(\.path)
        XCTAssertEqual(paths, [
            "../Packages/LocalPackageA",
        ])
    }
}
