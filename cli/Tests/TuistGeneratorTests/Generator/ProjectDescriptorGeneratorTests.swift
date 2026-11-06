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
    ) func generate_buildableFolders_anchorsConfigsAndAddsCrossTargetMembership() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let buildableFolder = temporaryPath.appending(component: "App")
        let xcconfig = buildableFolder.appending(components: "Supporting", "Configurations", "App-Debug.xcconfig")
        let infoPlist = buildableFolder.appending(components: "Supporting", "App-Info.plist")
        let sharedStub = buildableFolder.appending(component: "SharedStub.swift")

        let app = Target.test(
            name: "App",
            platform: .iOS,
            product: .app,
            infoPlist: .file(path: infoPlist),
            settings: Settings(
                base: [:],
                configurations: [.debug: Configuration(settings: [:], xcconfig: xcconfig)]
            ),
            buildableFolders: [
                BuildableFolder(
                    path: buildableFolder,
                    exceptions: BuildableFolderExceptions(exceptions: [
                        BuildableFolderException(
                            excluded: [],
                            compilerFlags: [:],
                            publicHeaders: [],
                            privateHeaders: [],
                            platformFilters: [:],
                            target: "AppTests",
                            included: [sharedStub]
                        ),
                    ]),
                    resolvedFiles: [BuildableFolderFile(path: sharedStub, compilerFlags: nil)]
                ),
            ]
        )
        let appTests = Target.test(name: "AppTests", platform: .iOS, product: .unitTests)
        let project = Project.test(
            path: temporaryPath,
            sourceRootPath: temporaryPath,
            name: "Project",
            targets: [app, appTests]
        )
        let appGraphTarget = GraphTarget(path: project.path, target: app, project: project)
        let appTestsGraphTarget = GraphTarget(path: project.path, target: appTests, project: project)
        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: appTestsGraphTarget.target.name, path: appTestsGraphTarget.path): [
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
        let appTarget = try #require(pbxproj.nativeTargets.first { $0.name == "App" })

        // The xcconfig is referenced through the synchronized root group anchor, not a flat file reference.
        let debugConfig = try #require(appTarget.buildConfigurationList?.configuration(name: "Debug"))
        #expect(debugConfig.baseConfiguration == nil)
        #expect(debugConfig.baseConfigurationReferenceRelativePath == "Supporting/Configurations/App-Debug.xcconfig")

        // The cross-target membership is a foreign-target exception set, not a flat reference.
        let group = try #require(
            appTarget.fileSystemSynchronizedGroups?
                .compactMap { $0 as? PBXFileSystemSynchronizedRootGroup }
                .first { $0.path == "App" }
        )
        let foreignSet = try #require(
            group.exceptions?
                .compactMap { $0 as? PBXFileSystemSynchronizedBuildFileExceptionSet }
                .first { $0.target?.name == "AppTests" }
        )
        #expect(foreignSet.membershipExceptions == ["SharedStub.swift"])

        // None of the buildable-folder files leak as flat file references at the project root.
        let fileReferenceNames = pbxproj.fileReferences.compactMap(\.path) + pbxproj.fileReferences.compactMap(\.name)
        #expect(!fileReferenceNames.contains { $0.hasSuffix("App-Debug.xcconfig") })
        #expect(!fileReferenceNames.contains { $0.hasSuffix("App-Info.plist") })
        #expect(!fileReferenceNames.contains { $0.hasSuffix("SharedStub.swift") })
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .inTemporaryDirectory,
        .withMockedXcodeController,
        arguments: [Product.staticFramework, .staticLibrary, .dynamicLibrary], [false, true]
    ) func generate_buildableFolders_catalogsHaveExactlyOneMembership(
        product: Product,
        explicitlyDeclared: Bool
    ) async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let folder = temporaryPath.appending(components: "Sources", "Feature UI")
        let assets = folder.appending(components: "Resources", "Assets.xcassets")
        let strings = folder.appending(components: "Resources", "Localizable.xcstrings")
        let swift = folder.appending(component: "Feature.swift")
        let image = folder.appending(components: "Resources", "image.png")
        let target = Target.test(
            name: "Feature",
            destinations: [.iPhone, .mac],
            product: product,
            sources: [],
            resources: .init(explicitlyDeclared ? [
                .file(path: assets, tags: ["images"], inclusionCondition: .when([.ios])),
                .file(path: strings, tags: ["strings"], inclusionCondition: .when([.ios])),
            ] : []),
            buildableFolders: [
                BuildableFolder(
                    path: folder,
                    exceptions: BuildableFolderExceptions(exceptions: []),
                    resolvedFiles: [assets, strings, swift, image].map { BuildableFolderFile(path: $0, compilerFlags: nil) }
                ),
            ]
        )
        let project = Project.test(
            path: temporaryPath,
            sourceRootPath: temporaryPath,
            name: "Project",
            targets: [target]
        )
        let contentHasher = MockContentHashing()
        given(contentHasher).hash(Parameter<Data>.any).willReturn("hash")
        let (mappedProject, _) = try await ResourcesProjectMapper(contentHasher: contentHasher).map(project: project)
        let graph = Graph.test(projects: [mappedProject.path: mappedProject])
        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock).selectedVersion().willReturn(Version(16, 0, 0))

        let generatedProject = try await subject.generate(
            project: mappedProject,
            graphTraverser: GraphTraverser(graph: graph)
        )

        let pbxproj = generatedProject.xcodeProj.pbxproj
        let mainTarget = try #require(pbxproj.nativeTargets.first { $0.name == "Feature" })
        let bundleTarget = try #require(pbxproj.nativeTargets.first { $0.name == "Project_Feature" })
        let catalogReferences = pbxproj.fileReferences.filter {
            $0.path?.hasSuffix(".xcassets") == true || $0.path?.hasSuffix(".xcstrings") == true
        }
        #expect(catalogReferences.count == (explicitlyDeclared ? 2 : 0))
        #expect(try mainTarget.resourcesBuildPhase() != nil)
        let debugConfig = try #require(mainTarget.buildConfigurationList?.configuration(name: "Debug"))
        #expect(debugConfig.buildSettings["PACKAGE_RESOURCE_BUNDLE_NAME"] == .string("Project_Feature"))
        let mainGroup = try #require(mainTarget.fileSystemSynchronizedGroups?.first)
        #expect(mainGroup == bundleTarget.fileSystemSynchronizedGroups?.first)
        let exclusions = mainGroup.exceptions?
            .compactMap { $0 as? PBXFileSystemSynchronizedBuildFileExceptionSet }
            .filter { $0.target == mainTarget }
            .flatMap { $0.membershipExceptions ?? [] } ?? []
        let catalogs = ["Resources/Assets.xcassets", "Resources/Localizable.xcstrings"]
        #expect(Set(exclusions) == Set(["Resources/image.png"] + (explicitlyDeclared ? catalogs : [])))
        let bundleExclusions = mainGroup.exceptions?
            .compactMap { $0 as? PBXFileSystemSynchronizedBuildFileExceptionSet }
            .filter { $0.target == bundleTarget }
            .flatMap { $0.membershipExceptions ?? [] } ?? []
        #expect(Set(bundleExclusions) == Set(["Feature.swift"] + (explicitlyDeclared ? catalogs : [])))
        if explicitlyDeclared {
            #expect(try mainTarget.sourcesBuildPhase()?.files?.filter { $0.file?.path?.hasSuffix(".xcassets") == true }
                .count == 1)
            #expect(try mainTarget.resourcesBuildPhase()?.files?.filter { $0.file?.path?.hasSuffix(".xcstrings") == true }
                .count == 1)
            let bundleFiles = try #require(try bundleTarget.resourcesBuildPhase()?.files)
            #expect(bundleFiles.count == 2)
            let bundleAsset = try #require(bundleFiles.first { $0.file?.path?.hasSuffix(".xcassets") == true })
            let bundleStrings = try #require(bundleFiles.first { $0.file?.path?.hasSuffix(".xcstrings") == true })
            #expect(bundleAsset.settings?["ASSET_TAGS"] == .array(["images"]))
            #expect(bundleStrings.settings?["ASSET_TAGS"] == .array(["strings"]))
            #expect(bundleAsset.platformFilter == "ios")
            #expect(bundleStrings.platformFilter == "ios")
        }

        let regeneratedProject = try await subject.generate(
            project: mappedProject,
            graphTraverser: GraphTraverser(graph: graph)
        )
        let output = try #require(try pbxproj.dataRepresentation(outputSettings: PBXOutputSettings()))
        let regeneratedOutput = try regeneratedProject.xcodeProj.pbxproj.dataRepresentation(outputSettings: PBXOutputSettings())
        #expect(output == regeneratedOutput)
        #expect(!String(decoding: output, as: UTF8.self).contains("TEMP_"))
        let jsonOutput = try pbxproj.xcprojData()
        let regeneratedJSONOutput = try regeneratedProject.xcodeProj.pbxproj.xcprojData()
        #expect(jsonOutput == regeneratedJSONOutput)
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
        let package = Package.local(path: localPackagePath)
        let project = Project.test(
            path: projectPath,
            sourceRootPath: projectPath,
            name: "Project",
            targets: [target, .test(name: "B", dependencies: [.package(product: "A", type: .runtime)])],
            packages: [package],
            packageTraits: [package.identity: ["FeatureA"]]
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
        #expect(rootObject.localPackages.first?.traits == ["FeatureA"])
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
        let package = Package.remote(url: "A", requirement: .exact("0.1"))
        let project = Project.test(
            path: temporaryPath,
            name: "Project",
            targets: [target, .test(name: "B", dependencies: [.package(product: "A", type: .runtime)])],
            packages: [package],
            packageTraits: [package.identity: []]
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
        #expect(rootObject.remotePackages.first?.traits == [])
    }
}
