import Foundation
import MockableTest
import Path
import struct TSCUtility.Version
import TuistCore
import TuistCoreTesting
import TuistSupport
import XcodeGraph
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class ProjectDescriptorGeneratorTests: TuistUnitTestCase {
    var subject: ProjectDescriptorGenerator!

    override func setUp() {
        super.setUp()
        given(swiftVersionProvider)
            .swiftVersion()
            .willReturn("5.2")

        subject = ProjectDescriptorGenerator()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_generate_testTargetIdentity() throws {
        // Given
        let temporaryPath = try temporaryPath()
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

        let testGraphTarget = GraphTarget(
            path: project.path,
            target: test,
            project: project
        )
        let appGraphTarget = GraphTarget(path: project.path, target: app, project: project)

        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: testGraphTarget.target.name, path: testGraphTarget.path): [
                    .target(name: appGraphTarget.target.name, path: appGraphTarget.path),
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

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
        let temporaryPath = try temporaryPath()
        let target = Target.test(name: "A")
        let project = Project.test(
            path: temporaryPath,
            name: "Project",
            targets: [target, .test(name: "B", dependencies: [.package(product: "A", type: .runtime)])],
            packages: [.remote(url: "A", requirement: .exact("0.1"))]
        )

        let graphTarget = GraphTarget.test(path: project.path, target: target, project: project)
        let graph = Graph.test(
            projects: [project.path: project],
            packages: [
                project.path: [
                    "A": .remote(url: "A", requirement: .exact("0.1")),
                ],
            ],
            dependencies: [
                .target(name: graphTarget.target.name, path: graphTarget.path): [
                    .packageProduct(path: project.path, product: "A", type: .runtime),
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxproj = got.xcodeProj.pbxproj
        XCTAssertEqual(pbxproj.objectVersion, 55)
        XCTAssertEqual(pbxproj.archiveVersion, Xcode.LastKnown.archiveVersion)
    }

    func test_objectVersion_when_xcode11() throws {
        xcodeController.selectedVersionStub = .success(Version(11, 0, 0))

        // Given
        let temporaryPath = try temporaryPath()
        let project = Project.test(
            path: temporaryPath,
            name: "Project",
            targets: []
        )
        let graph = Graph.test(
            projects: [project.path: project]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxproj = got.xcodeProj.pbxproj
        XCTAssertEqual(pbxproj.objectVersion, 55)
        XCTAssertEqual(pbxproj.archiveVersion, Xcode.LastKnown.archiveVersion)
    }

    func test_objectVersion_when_xcode10() throws {
        xcodeController.selectedVersionStub = .success(Version(10, 2, 1))

        // Given
        let temporaryPath = try temporaryPath()
        let project = Project.test(
            path: temporaryPath,
            name: "Project",
            targets: []
        )
        let graph = Graph.test(
            projects: [project.path: project]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxproj = got.xcodeProj.pbxproj
        XCTAssertEqual(pbxproj.objectVersion, 55)
        XCTAssertEqual(pbxproj.archiveVersion, Xcode.LastKnown.archiveVersion)
    }

    func test_knownRegions() throws {
        // Given
        let path = try temporaryPath()
        let graph = Graph.test(path: path)
        let graphTraverser = GraphTraverser(graph: graph)
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
                .test(resources: .init(
                    try resources.map {
                        .file(path: path.appending(try RelativePath(validating: $0)))
                    }
                )),
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
        let graph = Graph.test(path: path)
        let graphTraverser = GraphTraverser(graph: graph)
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

    func test_generate_setsCustomDefaultKnownRegions() throws {
        // Given
        let path = try temporaryPath()
        let graph = Graph.test(path: path)
        let graphTraverser = GraphTraverser(graph: graph)
        let project = Project.test(path: path, defaultKnownRegions: ["Base", "en-GB"], targets: [])

        // When
        let got = try subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxProject = try XCTUnwrap(try got.xcodeProj.pbxproj.rootProject())
        XCTAssertEqual(pbxProject.knownRegions, ["Base", "en-GB"])
    }

    func test_generate_setsOrganizationName() throws {
        // Given
        let path = try temporaryPath()
        let graph = Graph.test(path: path)
        let graphTraverser = GraphTraverser(graph: graph)
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
            "BuildIndependentTargetsInParallel": "YES",
            "ORGANIZATIONNAME": "tuist",
        ])
    }

    func test_generate_setsClassPrefix() throws {
        // Given
        let path = try temporaryPath()
        let graph = Graph.test(path: path)
        let graphTraverser = GraphTraverser(graph: graph)
        let project = Project.test(
            path: path,
            classPrefix: "TUIST",
            targets: []
        )

        // When
        let got = try subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxProject = try XCTUnwrap(try got.xcodeProj.pbxproj.rootProject())
        let attributes = try XCTUnwrap(pbxProject.attributes as? [String: String])
        XCTAssertEqual(attributes, [
            "BuildIndependentTargetsInParallel": "YES",
            "CLASSPREFIX": "TUIST",
        ])
    }

    func test_generate_setsResourcesTagsName() throws {
        // Given
        let path = try temporaryPath()
        let graph = Graph.test(path: path)
        let graphTraverser = GraphTraverser(graph: graph)
        let resources: [ResourceFileElement] = [
            .file(path: "/", tags: ["fileTag", "commonTag"]),
            .folderReference(path: "/", tags: ["folderTag", "commonTag"]),
        ]
        let project = Project.test(
            path: path,
            targets: [.test(resources: .init(resources))]
        )

        // When
        let got = try subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxProject = try XCTUnwrap(try got.xcodeProj.pbxproj.rootProject())
        let attributes = try XCTUnwrap(pbxProject.attributes as? [String: AnyHashable])
        XCTAssertEqual(attributes, [
            "BuildIndependentTargetsInParallel": "YES",
            "KnownAssetTags": ["fileTag", "folderTag", "commonTag"].sorted(),
        ])
    }

    func test_generate_setsDefaultDevelopmentRegion() throws {
        // Given
        let path = try temporaryPath()
        let graph = Graph.test(path: path)
        let graphTraverser = GraphTraverser(graph: graph)
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
        let graph = Graph.test(path: path)
        let graphTraverser = GraphTraverser(graph: graph)
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

    func test_generate_localSwiftPackageGroup() throws {
        // Given
        let project = Project.test(
            packages: [
                .local(path: try AbsolutePath(validating: "/LocalPackages/LocalPackageA")),
                .local(path: try AbsolutePath(validating: "/LocalPackages/LocalPackageB")),
            ]
        )

        let graph = Graph.test(projects: [project.path: project])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxproj = got.xcodeProj.pbxproj
        let rootGroup = try XCTUnwrap(pbxproj.rootGroup())
        let packagesGroup = rootGroup.group(named: "Packages")
        let packages = try XCTUnwrap(packagesGroup?.children)
        XCTAssertEqual(packages.map(\.name), ["LocalPackageA", "LocalPackageB"])
    }

    func test_generate_localSwiftPackagePaths() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let localPackagePath = try AbsolutePath(validating: "/LocalPackages/LocalPackageA")
        let target = Target.test(name: "A")
        let project = Project.test(
            path: projectPath,
            sourceRootPath: projectPath,
            name: "Project",
            targets: [target, .test(name: "B", dependencies: [.package(product: "A", type: .runtime)])],
            packages: [.local(path: localPackagePath)]
        )
        let graphTarget = GraphTarget(path: project.path, target: target, project: project)
        let graph = Graph.test(
            projects: [project.path: project],
            packages: [
                project.path: [
                    "A": .local(path: localPackagePath),
                ],
            ],
            dependencies: [
                .target(name: graphTarget.target.name, path: graphTarget.path): [
                    .packageProduct(path: project.path, product: "A", type: .runtime),
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxproj = got.xcodeProj.pbxproj
        let rootGroup = try XCTUnwrap(pbxproj.rootGroup())
        let packageGroup = try XCTUnwrap(rootGroup.group(named: "Packages"))
        let paths = packageGroup.children.compactMap(\.path)
        XCTAssertEqual(paths, [
            "../LocalPackages/LocalPackageA",
        ])
    }

    func test_generate_setsLastUpgradeCheck() throws {
        // Given
        let path = try temporaryPath()
        let graph = Graph.test(path: path)
        let graphTraverser = GraphTraverser(graph: graph)
        let project = Project.test(
            path: path,
            targets: [],
            lastUpgradeCheck: .init(12, 5, 1)
        )

        // When
        let got = try subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxProject = try XCTUnwrap(try got.xcodeProj.pbxproj.rootProject())
        let attributes = try XCTUnwrap(pbxProject.attributes as? [String: String])
        XCTAssertEqual(attributes, [
            "BuildIndependentTargetsInParallel": "YES",
            "LastUpgradeCheck": "1251",
        ])
    }
}
