import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import struct TSCUtility.Version
import TuistCore
import TuistSupport
import XcodeGraph
@testable import TuistGenerator
@testable import TuistTesting
@testable import XcodeProj

struct ProjectDescriptorGeneratorTests {
    var subject: ProjectDescriptorGenerator!

    init() throws {
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock)
            .swiftVersion()
            .willReturn("5.2")
        subject = ProjectDescriptorGenerator()
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func generate_testTargetIdentity() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
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

        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let generatedProject = try await subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxproj = generatedProject.xcodeProj.pbxproj
        let pbxproject = try pbxproj.rootProject()
        let nativeTargets = pbxproj.nativeTargets
        let attributes = pbxproject?.targetAttributes ?? [:]
        let appTarget = nativeTargets.first(where: { $0.name == "App" })
        #expect(attributes.contains { attribute in
            guard case let .targetReference(testTargetID) = attribute.value["TestTargetID"] else {
                return false
            }

            return attribute.key.name == "Tests" && testTargetID == appTarget

        } == true)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func objectVersion_when_xcode11_and_spm() async throws {
        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selectedVersion()
            .willReturn(Version(11, 0, 0))

        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
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
        let got = try await subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxproj = got.xcodeProj.pbxproj
        #expect(pbxproj.objectVersion == 55)
        #expect(pbxproj.archiveVersion == Xcode.LastKnown.archiveVersion)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func objectVersion_when_xcode11() async throws {
        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selectedVersion()
            .willReturn(Version(11, 0, 0))

        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
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
        let got = try await subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxproj = got.xcodeProj.pbxproj
        #expect(pbxproj.objectVersion == 55)
        #expect(pbxproj.archiveVersion == Xcode.LastKnown.archiveVersion)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func objectVersion_when_xcode10() async throws {
        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selectedVersion()
            .willReturn(Version(10, 2, 1))

        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
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
        let got = try await subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxproj = got.xcodeProj.pbxproj
        #expect(pbxproj.objectVersion == 55)
        #expect(pbxproj.archiveVersion == Xcode.LastKnown.archiveVersion)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func test_knownRegions() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
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

        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxProject = try #require(try got.xcodeProj.pbxproj.rootProject())
        #expect(pbxProject.knownRegions == [
            "Base",
            "en",
            "fr",
        ])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func generate_setsDefaultKnownRegions() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let graph = Graph.test(path: path)
        let graphTraverser = GraphTraverser(graph: graph)
        let project = Project.test(
            path: path,
            targets: []
        )

        // When
        let got = try await subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxProject = try #require(try got.xcodeProj.pbxproj.rootProject())
        #expect(pbxProject.knownRegions == [
            "Base",
            "en",
        ])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func generate_setsCustomDefaultKnownRegions() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let graph = Graph.test(path: path)
        let graphTraverser = GraphTraverser(graph: graph)
        let project = Project.test(path: path, defaultKnownRegions: ["Base", "en-GB"], targets: [])

        // When
        let got = try await subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxProject = try #require(try got.xcodeProj.pbxproj.rootProject())
        #expect(pbxProject.knownRegions == ["Base", "en-GB"])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func generate_setsOrganizationName() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let graph = Graph.test(path: path)
        let graphTraverser = GraphTraverser(graph: graph)
        let project = Project.test(
            path: path,
            organizationName: "tuist",
            targets: []
        )

        // When
        let got = try await subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxProject = try #require(try got.xcodeProj.pbxproj.rootProject())
        let attributes = pbxProject.attributes
        #expect(attributes == [
            "BuildIndependentTargetsInParallel": "YES",
            "ORGANIZATIONNAME": "tuist",
        ])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func generate_setsClassPrefix() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let graph = Graph.test(path: path)
        let graphTraverser = GraphTraverser(graph: graph)
        let project = Project.test(
            path: path,
            classPrefix: "TUIST",
            targets: []
        )

        // When
        let got = try await subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxProject = try #require(try got.xcodeProj.pbxproj.rootProject())
        let attributes = pbxProject.attributes
        #expect(attributes == [
            "BuildIndependentTargetsInParallel": "YES",
            "CLASSPREFIX": "TUIST",
        ])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func generate_setsResourcesTagsName() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
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

        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxProject = try #require(try got.xcodeProj.pbxproj.rootProject())
        let attributes = pbxProject.attributes
        #expect(attributes == [
            "BuildIndependentTargetsInParallel": "YES",
            "KnownAssetTags": .array(["fileTag", "folderTag", "commonTag"].sorted()),
        ])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func generate_setsDefaultDevelopmentRegion() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let graph = Graph.test(path: path)
        let graphTraverser = GraphTraverser(graph: graph)
        let project = Project.test(
            path: path,
            targets: []
        )

        // When
        let got = try await subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxProject = try #require(try got.xcodeProj.pbxproj.rootProject())
        #expect(pbxProject.developmentRegion == "en")
    }

    func test_generate_setsDevelopmentRegion() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let graph = Graph.test(path: path)
        let graphTraverser = GraphTraverser(graph: graph)
        let project = Project.test(
            path: path,
            developmentRegion: "de",
            targets: []
        )

        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxProject = try #require(try got.xcodeProj.pbxproj.rootProject())
        #expect(pbxProject.developmentRegion == "de")
    }

    func test_generate_localSwiftPackageGroup() async throws {
        // Given
        let project = Project.test(
            packages: [
                .local(path: try AbsolutePath(validating: "/LocalPackages/LocalPackageA")),
                .local(path: try AbsolutePath(validating: "/LocalPackages/LocalPackageB")),
            ]
        )

        let graph = Graph.test(projects: [project.path: project])
        let graphTraverser = GraphTraverser(graph: graph)

        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxproj = got.xcodeProj.pbxproj
        let rootGroup = try #require(try pbxproj.rootGroup())
        let packagesGroup = rootGroup.group(named: "Packages")
        let packages = try #require(packagesGroup?.children)
        #expect(packages.map(\.name) == ["LocalPackageA", "LocalPackageB"])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func generate_localSwiftPackagePaths() async throws {
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

        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxproj = got.xcodeProj.pbxproj
        let rootGroup = try #require(try pbxproj.rootGroup())
        let packageGroup = try #require(rootGroup.group(named: "Packages"))
        let paths = packageGroup.children.compactMap(\.path)
        #expect(paths == [
            "../LocalPackages/LocalPackageA",
        ])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func generate_setsLastUpgradeCheck() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let graph = Graph.test(path: path)
        let graphTraverser = GraphTraverser(graph: graph)
        let project = Project.test(
            path: path,
            targets: [],
            lastUpgradeCheck: .init(12, 5, 1)
        )

        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxProject = try #require(try got.xcodeProj.pbxproj.rootProject())
        let attributes = pbxProject.attributes
        #expect(attributes == [
            "BuildIndependentTargetsInParallel": "YES",
            "LastUpgradeCheck": "1251",
        ])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func generate_localSwiftPackages() async throws {
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

        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxproj = got.xcodeProj.pbxproj
        let rootObject = try #require(pbxproj.rootObject)
        let pbxobjects = try rootObject.objects()
        let localPackagePaths = rootObject.localPackages.compactMap(\.relativePath)
        let localSwiftPackageReferencePaths = pbxobjects.localSwiftPackageReferences.values.compactMap(\.relativePath)
        let remotePackageNames = rootObject.remotePackages.compactMap(\.name)
        let remoteSwiftPackageReferenceNames = pbxobjects.remoteSwiftPackageReferences.values.compactMap(\.name)
        #expect(localPackagePaths == [
            "../LocalPackages/LocalPackageA",
        ])
        #expect(localSwiftPackageReferencePaths == [
            "../LocalPackages/LocalPackageA",
        ])
        #expect(remotePackageNames.isEmpty == true)
        #expect(remoteSwiftPackageReferenceNames.isEmpty == true)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func generate_remoteSwiftPackages() async throws {
        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
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
        let got = try await subject.generate(project: project, graphTraverser: graphTraverser)

        // Then
        let pbxproj = got.xcodeProj.pbxproj
        let rootObject = try #require(pbxproj.rootObject)
        let pbxobjects = try rootObject.objects()
        let localPackagePaths = rootObject.localPackages.compactMap(\.relativePath)
        let localSwiftPackageReferencePaths = pbxobjects.localSwiftPackageReferences.values.compactMap(\.relativePath)
        let remotePackageNames = rootObject.remotePackages.compactMap(\.name)
        let remoteSwiftPackageReferenceNames = pbxobjects.remoteSwiftPackageReferences.values.compactMap(\.name)
        #expect(localPackagePaths.isEmpty == true)
        #expect(localSwiftPackageReferencePaths.isEmpty == true)
        #expect(remotePackageNames == [
            "A",
        ])
        #expect(remoteSwiftPackageReferenceNames == [
            "A",
        ])
    }
}
