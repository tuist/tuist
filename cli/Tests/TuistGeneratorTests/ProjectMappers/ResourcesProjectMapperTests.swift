import Foundation
import Mockable
import Path
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
import XCTest

@testable import TuistGenerator

/// Bundle name is irrelevant if the target supports resources.
private let irrelevantBundleName = ""

final class ResourcesProjectMapperTests: TuistUnitTestCase {
    var project: Project!
    var buildableFolderChecker: MockBuildableFolderChecking!
    var subject: ResourcesProjectMapper!
    var contentHasher: MockContentHashing!

    override func setUp() {
        super.setUp()
        contentHasher = .init()
        buildableFolderChecker = MockBuildableFolderChecking()
        subject = ResourcesProjectMapper(contentHasher: contentHasher, buildableFolderChecker: buildableFolderChecker)

        given(contentHasher)
            .hash(Parameter<Data>.any)
            .willProduce { String(data: $0, encoding: .utf8)! }
    }

    override func tearDown() {
        project = nil
        subject = nil
        super.tearDown()
    }

    func test_map_when_a_target_that_has_resources_and_doesnt_supports_them() async throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/image.png")]
        let target = Target.test(product: .staticLibrary, sources: ["/Absolute/File.swift"], resources: .init(resources))
        project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // Got
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        XCTAssertEqual(gotSideEffects.count, 1)
        let sideEffect = try XCTUnwrap(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            XCTFail("Expected file descriptor")
            return
        }
        let expectedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(targetName: target.name, bundleName: "\(project.name)_\(target.name)", target: target, in: project)
        XCTAssertEqual(file.path, expectedPath)
        XCTAssertEqual(file.contents, expectedContents.data(using: .utf8))

        // Then: Targets
        XCTAssertEqual(gotProject.targets.count, 2)
        let gotTarget = try XCTUnwrap(gotProject.targets.values.sorted().last)
        XCTAssertEqual(gotTarget.name, target.name)
        XCTAssertEqual(gotTarget.product, target.product)
        XCTAssertEqual(gotTarget.resources.resources.count, 0)
        XCTAssertEqual(gotTarget.sources.count, 2)
        XCTAssertEqual(gotTarget.sources.last?.path, expectedPath)
        XCTAssertNotNil(gotTarget.sources.last?.contentHash)
        XCTAssertEqual(gotTarget.dependencies.count, 1)
        XCTAssertEqual(
            gotTarget.dependencies.first,
            TargetDependency.target(name: "\(project.name)_\(target.name)", condition: .when([.ios]))
        )

        let resourcesTarget = try XCTUnwrap(gotProject.targets.values.sorted().first)
        XCTAssertEqual(resourcesTarget.name, "\(project.name)_\(target.name)")
        XCTAssertEqual(resourcesTarget.product, .bundle)
        XCTAssertEqual(resourcesTarget.destinations, target.destinations)
        XCTAssertEqual(resourcesTarget.bundleId, "\(target.bundleId).generated.resources")
        XCTAssertEqual(resourcesTarget.deploymentTargets, target.deploymentTargets)
        XCTAssertEqual(resourcesTarget.filesGroup, target.filesGroup)
        XCTAssertEqual(resourcesTarget.resources.resources, resources)
        XCTAssertEqual(resourcesTarget.settings?.base, [
            "SKIP_INSTALL": "YES",
            "CODE_SIGNING_ALLOWED": "NO",
            "GENERATE_MASTER_OBJECT_FILE": "NO",
            "VERSIONING_SYSTEM": "",
        ])
    }

    func test_map_when_an_external_objc_target_that_has_resources_and_supports_them() async throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/image.png")]
        let target = Target.test(product: .framework, sources: ["/Absolute/File.m"], resources: .init(resources))
        project = Project.test(targets: [target], type: .external(hash: nil))
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // Got
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertEqual(project, gotProject)
    }

    func testMap_whenDisableBundleAccessorsIsTrue_doesNotGenerateAccessors() async throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/image.png")]
        let target = Target.test(product: .staticLibrary, resources: .init(resources))
        project = Project.test(
            options: .test(
                disableBundleAccessors: true
            ),
            targets: [target]
        )
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // Got
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        XCTAssertEqual(project, gotProject)
        XCTAssertEqual(gotSideEffects, [])
    }

    func test_map_when_no_sources() async throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/image.png")]
        let target = Target.test(product: .staticLibrary, sources: [], resources: .init(resources))
        project = Project.test(
            targets: [target]
        )
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // Got
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        XCTAssertEqual(gotSideEffects, [])
        XCTAssertEqual(gotProject.targets.count, 2)

        let gotTarget = try XCTUnwrap(gotProject.targets.values.sorted().last)
        XCTAssertEqual(gotTarget.name, target.name)
        XCTAssertEqual(gotTarget.product, target.product)
        XCTAssertEqual(gotTarget.resources.resources.count, 0)
        XCTAssertEqual(gotTarget.sources.count, 0)
        XCTAssertEqual(gotTarget.dependencies.count, 1)
        XCTAssertEqual(
            gotTarget.dependencies.first,
            TargetDependency.target(name: "\(project.name)_\(target.name)", condition: .when([.ios]))
        )

        let resourcesTarget = try XCTUnwrap(gotProject.targets.values.sorted().first)
        XCTAssertEqual(resourcesTarget.name, "\(project.name)_\(target.name)")
        XCTAssertEqual(resourcesTarget.product, .bundle)
        XCTAssertEqual(resourcesTarget.destinations, target.destinations)
        XCTAssertEqual(resourcesTarget.bundleId, "\(target.bundleId).generated.resources")
        XCTAssertEqual(resourcesTarget.deploymentTargets, target.deploymentTargets)
        XCTAssertEqual(resourcesTarget.filesGroup, target.filesGroup)
        XCTAssertEqual(resourcesTarget.resources.resources, resources)
    }

    func test_map_when_no_sources_but_buildable_folders() async throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/image.png")]
        let buildableFolders = [BuildableFolder(
            path: try AbsolutePath(validating: "/sources"),
            exceptions: BuildableFolderExceptions(exceptions: []),
            resolvedFiles: []
        )]
        let target = Target.test(
            product: .staticLibrary,
            sources: [],
            resources: .init(resources),
            buildableFolders: buildableFolders
        )
        project = Project.test(
            targets: [target]
        )
        given(buildableFolderChecker).containsResources(.value(buildableFolders)).willReturn(true)
        given(buildableFolderChecker).containsSources(.value(buildableFolders)).willReturn(true)

        // Got
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        XCTAssertEqual(gotSideEffects.count, 1)
        let sideEffect = try XCTUnwrap(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            XCTFail("Expected file descriptor")
            return
        }
        let expectedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(targetName: target.name, bundleName: "\(project.name)_\(target.name)", target: target, in: project)
        XCTAssertEqual(file.path, expectedPath)
        XCTAssertEqual(file.contents, expectedContents.data(using: .utf8))

        let gotTarget = try XCTUnwrap(gotProject.targets.values.sorted().last)
        XCTAssertEqual(gotTarget.name, target.name)
        XCTAssertEqual(gotTarget.product, target.product)
        XCTAssertEqual(gotTarget.resources.resources.count, 0)
        XCTAssertEqual(gotTarget.sources.count, 1)
        XCTAssertEqual(gotTarget.dependencies.count, 1)
        XCTAssertEqual(
            gotTarget.dependencies.first,
            TargetDependency.target(name: "\(project.name)_\(target.name)", condition: .when([.ios]))
        )

        let resourcesTarget = try XCTUnwrap(gotProject.targets.values.sorted().first)
        XCTAssertEqual(resourcesTarget.name, "\(project.name)_\(target.name)")
        XCTAssertEqual(resourcesTarget.product, .bundle)
        XCTAssertEqual(resourcesTarget.destinations, target.destinations)
        XCTAssertEqual(resourcesTarget.bundleId, "\(target.bundleId).generated.resources")
        XCTAssertEqual(resourcesTarget.deploymentTargets, target.deploymentTargets)
        XCTAssertEqual(resourcesTarget.filesGroup, target.filesGroup)
        XCTAssertEqual(resourcesTarget.resources.resources, resources)
    }

    func test_map_when_no_sources_and_resources_but_buildable_folders() async throws {
        // Given
        let buildableFolders = [
            BuildableFolder(
                path: try AbsolutePath(validating: "/sources"),
                exceptions: BuildableFolderExceptions(exceptions: []),
                resolvedFiles: [
                    BuildableFolderFile(path: try AbsolutePath(validating: "/sources/File.swift"), compilerFlags: nil),
                ]
            ),
            BuildableFolder(
                path: try AbsolutePath(validating: "/resources"),
                exceptions: BuildableFolderExceptions(exceptions: []),
                resolvedFiles: [
                    BuildableFolderFile(
                        path: try AbsolutePath(validating: "/resources/en.lproj/Localizable.strings"),
                        compilerFlags: nil
                    ),
                    BuildableFolderFile(path: try AbsolutePath(validating: "/resources/Assets.xcassets"), compilerFlags: nil),
                ]
            ),
        ]
        let target = Target.test(
            product: .staticLibrary,
            sources: [],
            resources: ResourceFileElements([]),
            buildableFolders: buildableFolders
        )
        project = Project.test(
            targets: [target]
        )
        given(buildableFolderChecker).containsResources(.value(buildableFolders)).willReturn(true)
        given(buildableFolderChecker).containsSources(.value(buildableFolders)).willReturn(true)

        // Got
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        XCTAssertEqual(gotSideEffects.count, 1)
        let sideEffect = try XCTUnwrap(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            XCTFail("Expected file descriptor")
            return
        }
        let expectedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(targetName: target.name, bundleName: "\(project.name)_\(target.name)", target: target, in: project)
        XCTAssertEqual(file.path, expectedPath)
        XCTAssertEqual(file.contents, expectedContents.data(using: .utf8))

        let gotTarget = try XCTUnwrap(gotProject.targets.values.sorted().last)
        XCTAssertEqual(gotTarget.name, target.name)
        XCTAssertEqual(gotTarget.product, target.product)
        XCTAssertEqual(gotTarget.resources.resources.count, 0)
        XCTAssertEqual(gotTarget.sources.count, 1)
        XCTAssertEqual(gotTarget.dependencies.count, 1)
        XCTAssertEqual(
            gotTarget.dependencies.first,
            TargetDependency.target(name: "\(project.name)_\(target.name)", condition: .when([.ios]))
        )

        let resourcesTarget = try XCTUnwrap(gotProject.targets.values.sorted().first)
        XCTAssertEqual(resourcesTarget.name, "\(project.name)_\(target.name)")
        XCTAssertEqual(resourcesTarget.product, .bundle)
        XCTAssertEqual(resourcesTarget.destinations, target.destinations)
        XCTAssertEqual(resourcesTarget.bundleId, "\(target.bundleId).generated.resources")
        XCTAssertEqual(resourcesTarget.deploymentTargets, target.deploymentTargets)
        XCTAssertEqual(resourcesTarget.filesGroup, target.filesGroup)
        XCTAssertEqual(resourcesTarget.buildableFolders, [buildableFolders[1]])
        XCTAssertEqual(gotTarget.buildableFolders, [buildableFolders[0]])
    }

    func test_map_when_buildable_folder_contains_sources_and_resources() async throws {
        // Given
        let sharedFolderPath = try AbsolutePath(validating: "/shared")
        let swiftFilePath = try AbsolutePath(validating: "/shared/File.swift")
        let assetsPath = try AbsolutePath(validating: "/shared/Assets.xcassets")

        let buildableFolder = BuildableFolder(
            path: sharedFolderPath,
            exceptions: BuildableFolderExceptions(exceptions: []),
            resolvedFiles: [
                BuildableFolderFile(path: swiftFilePath, compilerFlags: nil),
                BuildableFolderFile(path: assetsPath, compilerFlags: nil),
            ]
        )

        let target = Target.test(
            product: .staticFramework,
            sources: [],
            resources: ResourceFileElements([]),
            buildableFolders: [buildableFolder]
        )
        project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([buildableFolder])).willReturn(true)
        given(buildableFolderChecker).containsSources(.value([buildableFolder])).willReturn(true)

        // When
        let (gotProject, _) = try await subject.map(project: project)

        // Then
        let gotTarget = try XCTUnwrap(gotProject.targets.values.sorted().last)
        XCTAssertEqual(gotTarget.buildableFolders.count, 1)
        let expectedSourcesFolder = BuildableFolder(
            path: sharedFolderPath,
            exceptions: BuildableFolderExceptions(
                exceptions: [
                    BuildableFolderException(
                        excluded: [assetsPath],
                        compilerFlags: [:],
                        publicHeaders: [],
                        privateHeaders: []
                    ),
                ]
            ),
            resolvedFiles: [
                BuildableFolderFile(path: swiftFilePath, compilerFlags: nil),
            ]
        )
        XCTAssertEqual(gotTarget.buildableFolders.first, expectedSourcesFolder)

        let resourcesTarget = try XCTUnwrap(gotProject.targets.values.sorted().first)
        XCTAssertEqual(resourcesTarget.buildableFolders.count, 1)
        let expectedResourcesFolder = BuildableFolder(
            path: sharedFolderPath,
            exceptions: BuildableFolderExceptions(
                exceptions: [
                    BuildableFolderException(
                        excluded: [swiftFilePath],
                        compilerFlags: [:],
                        publicHeaders: [],
                        privateHeaders: []
                    ),
                ]
            ),
            resolvedFiles: [
                BuildableFolderFile(path: assetsPath, compilerFlags: nil),
            ]
        )
        XCTAssertEqual(resourcesTarget.buildableFolders.first, expectedResourcesFolder)
    }

    func test_map_when_nested_buildable_folders_share_sources_and_resources() async throws {
        // Given
        let rootPath = try AbsolutePath(validating: "/MyTarget")
        let sourcesPath = try AbsolutePath(validating: "/MyTarget/Sources")
        let nestedResourcesPath = try AbsolutePath(validating: "/MyTarget/Sources/Resources")
        let swiftFile = try AbsolutePath(validating: "/MyTarget/Sources/File.swift")
        let assetFolder = try AbsolutePath(validating: "/MyTarget/Sources/Resources/Asset.xcassets")

        let buildableFolders = [
            BuildableFolder(
                path: rootPath,
                exceptions: BuildableFolderExceptions(exceptions: []),
                resolvedFiles: [
                    BuildableFolderFile(path: swiftFile, compilerFlags: nil),
                    BuildableFolderFile(path: assetFolder, compilerFlags: nil),
                ]
            ),
            BuildableFolder(
                path: sourcesPath,
                exceptions: BuildableFolderExceptions(exceptions: []),
                resolvedFiles: [
                    BuildableFolderFile(path: swiftFile, compilerFlags: nil),
                    BuildableFolderFile(path: assetFolder, compilerFlags: nil),
                ]
            ),
            BuildableFolder(
                path: nestedResourcesPath,
                exceptions: BuildableFolderExceptions(exceptions: []),
                resolvedFiles: [
                    BuildableFolderFile(path: assetFolder, compilerFlags: nil),
                ]
            ),
        ]

        let target = Target.test(
            product: .staticFramework,
            sources: [],
            resources: ResourceFileElements([]),
            buildableFolders: buildableFolders
        )
        project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value(buildableFolders)).willReturn(true)
        given(buildableFolderChecker).containsSources(.value(buildableFolders)).willReturn(true)

        // When
        let (gotProject, _) = try await subject.map(project: project)

        // Then
        let gotTarget = try XCTUnwrap(gotProject.targets.values.sorted().last)
        XCTAssertEqual(gotTarget.buildableFolders.count, 2)

        let expectedRootSources = BuildableFolder(
            path: rootPath,
            exceptions: BuildableFolderExceptions(
                exceptions: [
                    BuildableFolderException(
                        excluded: [assetFolder],
                        compilerFlags: [:],
                        publicHeaders: [],
                        privateHeaders: []
                    ),
                ]
            ),
            resolvedFiles: [
                BuildableFolderFile(path: swiftFile, compilerFlags: nil),
            ]
        )

        XCTAssertTrue(gotTarget.buildableFolders.contains(expectedRootSources))
        let expectedSourcesFolderSourcesView = BuildableFolder(
            path: sourcesPath,
            exceptions: BuildableFolderExceptions(
                exceptions: [
                    BuildableFolderException(
                        excluded: [assetFolder],
                        compilerFlags: [:],
                        publicHeaders: [],
                        privateHeaders: []
                    ),
                ]
            ),
            resolvedFiles: [
                BuildableFolderFile(path: swiftFile, compilerFlags: nil),
            ]
        )
        XCTAssertTrue(gotTarget.buildableFolders.contains(expectedSourcesFolderSourcesView))

        let resourcesTarget = try XCTUnwrap(gotProject.targets.values.sorted().first)
        XCTAssertEqual(resourcesTarget.buildableFolders.count, 3)

        let expectedRootResources = BuildableFolder(
            path: rootPath,
            exceptions: BuildableFolderExceptions(
                exceptions: [
                    BuildableFolderException(
                        excluded: [swiftFile],
                        compilerFlags: [:],
                        publicHeaders: [],
                        privateHeaders: []
                    ),
                ]
            ),
            resolvedFiles: [
                BuildableFolderFile(path: assetFolder, compilerFlags: nil),
            ]
        )

        XCTAssertTrue(resourcesTarget.buildableFolders.contains(expectedRootResources))
        let expectedSourcesFolderResourcesView = BuildableFolder(
            path: sourcesPath,
            exceptions: BuildableFolderExceptions(
                exceptions: [
                    BuildableFolderException(
                        excluded: [swiftFile],
                        compilerFlags: [:],
                        publicHeaders: [],
                        privateHeaders: []
                    ),
                ]
            ),
            resolvedFiles: [
                BuildableFolderFile(path: assetFolder, compilerFlags: nil),
            ]
        )
        XCTAssertTrue(resourcesTarget.buildableFolders.contains(expectedSourcesFolderResourcesView))
        XCTAssertTrue(resourcesTarget.buildableFolders.contains(buildableFolders[2]))
    }

    func test_map_when_a_target_that_has_core_data_models_and_doesnt_supports_them() async throws {
        // Given

        let coreDataModels: [CoreDataModel] =
            [CoreDataModel(path: "/data.xcdatamodeld", versions: ["/data.xcdatamodeld"], currentVersion: "1")]
        let target = Target.test(product: .staticLibrary, sources: ["/Absolute/File.swift"], coreDataModels: coreDataModels)
        project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // Got
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        XCTAssertEqual(gotSideEffects.count, 1)
        let sideEffect = try XCTUnwrap(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            XCTFail("Expected file descriptor")
            return
        }
        let expectedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(targetName: target.name, bundleName: "\(project.name)_\(target.name)", target: target, in: project)
        XCTAssertEqual(file.path, expectedPath)
        XCTAssertEqual(file.contents, expectedContents.data(using: .utf8))

        // Then: Targets
        XCTAssertEqual(gotProject.targets.count, 2)
        let gotTarget = try XCTUnwrap(gotProject.targets.values.sorted().last)
        XCTAssertEqual(gotTarget.name, target.name)
        XCTAssertEqual(gotTarget.product, target.product)
        XCTAssertEqual(gotTarget.resources.resources.count, 0)
        XCTAssertEqual(gotTarget.sources.count, 2)
        XCTAssertEqual(gotTarget.sources.last?.path, expectedPath)
        XCTAssertNotNil(gotTarget.sources.last?.contentHash)
        XCTAssertEqual(gotTarget.dependencies.count, 1)
        XCTAssertEqual(
            gotTarget.dependencies.first,
            TargetDependency.target(name: "\(project.name)_\(target.name)", condition: .when([.ios]))
        )

        let resourcesTarget = try XCTUnwrap(gotProject.targets.values.sorted().first)
        XCTAssertEqual(resourcesTarget.name, "\(project.name)_\(target.name)")
        XCTAssertEqual(resourcesTarget.product, .bundle)
        XCTAssertEqual(resourcesTarget.destinations, target.destinations)
        XCTAssertEqual(resourcesTarget.bundleId, "\(target.bundleId).generated.resources")
        XCTAssertEqual(resourcesTarget.deploymentTargets, target.deploymentTargets)
        XCTAssertEqual(resourcesTarget.filesGroup, target.filesGroup)
        XCTAssertEqual(resourcesTarget.coreDataModels, coreDataModels)
    }

    func test_map_when_a_target_that_has_resources_and_supports_them() async throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/image.png")]
        let target = Target.test(product: .framework, sources: ["/Absolute/File.swift"], resources: .init(resources))
        project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // Got
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        XCTAssertEqual(gotSideEffects.count, 1)
        let sideEffect = try XCTUnwrap(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            XCTFail("Expected file descriptor")
            return
        }
        let expectedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(targetName: target.name, bundleName: irrelevantBundleName, target: target, in: project)
        XCTAssertEqual(file.path, expectedPath)
        XCTAssertEqual(file.contents, expectedContents.data(using: .utf8))

        // Then: Targets
        XCTAssertEqual(gotProject.targets.count, 1)
        let gotTarget = try XCTUnwrap(gotProject.targets.values.sorted().first)
        XCTAssertEqual(gotTarget.name, target.name)
        XCTAssertEqual(gotTarget.product, target.product)
        XCTAssertEqual(gotTarget.resources.resources, resources)
        XCTAssertEqual(gotTarget.sources.count, 2)
        XCTAssertEqual(gotTarget.sources.last?.path, expectedPath)
        XCTAssertNotNil(gotTarget.sources.last?.contentHash)
        XCTAssertEqual(gotTarget.dependencies.count, 0)
    }

    func test_map_when_a_target_that_has_no_resources_but_has_metal_source_files_and_supports_them() async throws {
        // Given
        let target = Target.test(
            product: .framework,
            sources: ["/Absolute/File.swift", "/Absolute/File.metal"],
            resources: .init([])
        )
        project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // Got
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        XCTAssertEqual(gotSideEffects.count, 1)
        let sideEffect = try XCTUnwrap(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            XCTFail("Expected file descriptor")
            return
        }
        let expectedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(targetName: target.name, bundleName: irrelevantBundleName, target: target, in: project)
        XCTAssertEqual(file.path, expectedPath)
        XCTAssertEqual(file.contents, expectedContents.data(using: .utf8))

        // Then: Targets
        XCTAssertEqual(gotProject.targets.count, 1)
        let gotTarget = try XCTUnwrap(gotProject.targets.values.sorted().first)
        XCTAssertEqual(gotTarget.name, target.name)
        XCTAssertEqual(gotTarget.product, target.product)
        XCTAssertEqual(gotTarget.sources.count, 3)
        XCTAssertEqual(gotTarget.sources.last?.path, expectedPath)
        XCTAssertNotNil(gotTarget.sources.last?.contentHash)
        XCTAssertEqual(gotTarget.dependencies.count, 0)
    }

    func test_map_when_a_target_that_has_core_data_models_and_supports_them() async throws {
        // Given
        let coreDataModels: [CoreDataModel] =
            [CoreDataModel(path: "/data.xcdatamodeld", versions: ["/data.xcdatamodeld"], currentVersion: "1")]
        let target = Target.test(product: .framework, sources: ["/Absolute/File.swift"], coreDataModels: coreDataModels)
        project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // Got
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        XCTAssertEqual(gotSideEffects.count, 1)
        let sideEffect = try XCTUnwrap(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            XCTFail("Expected file descriptor")
            return
        }
        let expectedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(targetName: target.name, bundleName: irrelevantBundleName, target: target, in: project)
        XCTAssertEqual(file.path, expectedPath)
        XCTAssertEqual(file.contents, expectedContents.data(using: .utf8))

        // Then: Targets
        XCTAssertEqual(gotProject.targets.count, 1)
        let gotTarget = try XCTUnwrap(gotProject.targets.values.sorted().first)
        XCTAssertEqual(gotTarget.name, target.name)
        XCTAssertEqual(gotTarget.product, target.product)
        XCTAssertEqual(gotTarget.coreDataModels, coreDataModels)
        XCTAssertEqual(gotTarget.sources.count, 2)
        XCTAssertEqual(gotTarget.sources.last?.path, expectedPath)
        XCTAssertNotNil(gotTarget.sources.last?.contentHash)
        XCTAssertEqual(gotTarget.dependencies.count, 0)
    }

    func test_map_when_a_target_has_no_resources() async throws {
        // Given
        let resources: [ResourceFileElement] = []
        let target = Target.test(product: .framework, resources: .init(resources))
        project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // Got
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then
        XCTAssertEqual(Array(gotProject.targets.values), [target])
        XCTAssertEmpty(gotSideEffects)
    }

    func test_map_when_a_target_does_not_support_sources() async throws {
        // Given
        let resources: [ResourceFileElement] = [
            .file(path: "/Some/ResourceA"),
            .file(path: "/Some/ResourceB"),
        ]
        let target = Target.test(product: .bundle, resources: .init(resources))
        project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // Got
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then
        XCTAssertEqual(Array(gotProject.targets.values), [target])
        XCTAssertEmpty(gotSideEffects)
    }

    func test_map_when_a_target_that_has_name_with_hyphen() async throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/image.png")]
        let target = Target.test(
            name: "test-tuist",
            product: .staticLibrary,
            sources: ["/Absolute/File.swift"],
            resources: .init(resources)
        )
        project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // Got
        let (_, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        XCTAssertEqual(gotSideEffects.count, 1)
        let sideEffect = try XCTUnwrap(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            XCTFail("Expected file descriptor")
            return
        }
        let expectedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name.camelized.uppercasingFirst).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(targetName: target.name, bundleName: "\(project.name)_test_tuist", target: target, in: project)
        XCTAssertEqual(file.path, expectedPath)
        XCTAssertEqual(file.contents, expectedContents.data(using: .utf8))
    }

    func test_map_when_a_project_is_external_target_has_swift_source_but_no_resource_files() async throws {
        // Given
        let sources: [SourceFile] = ["/ViewController.swift"]
        let resources: [ResourceFileElement] = []
        let target = Target.test(product: .staticLibrary, sources: sources, resources: .init(resources))
        project = Project.test(
            path: try AbsolutePath(validating: "/AbsolutePath/Project"),
            targets: [target],
            type: .external(hash: nil)
        )
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // Got
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then
        XCTAssertEqual(Array(gotProject.targets.values), [target])
        XCTAssertEmpty(gotSideEffects)
    }

    func test_map_when_a_project_is_not_external_target_has_swift_source_but_no_resource_files() async throws {
        // Given
        let sources: [SourceFile] = ["/ViewController.swift"]
        let resources: [ResourceFileElement] = []
        let target = Target.test(product: .staticLibrary, sources: sources, resources: .init(resources))
        project = Project.test(path: try AbsolutePath(validating: "/AbsolutePath/Project"), targets: [target], type: .local)
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // Got
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then
        XCTAssertEqual(Array(gotProject.targets.values), [target])
        XCTAssertEmpty(gotSideEffects)
    }

    func test_map_when_a_project_is_external_target_has_swift_source_and_resource_files() async throws {
        // Given
        let sources: [SourceFile] = ["/ViewController.swift"]
        let resources: [ResourceFileElement] = [.file(path: "/AbsolutePath/Project/Resources/image.png")]
        let target = Target.test(product: .staticLibrary, sources: sources, resources: .init(resources))
        project = Project.test(
            path: try AbsolutePath(validating: "/AbsolutePath/Project"),
            targets: [target],
            type: .external(hash: nil)
        )
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // Got
        let (_, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        try verify(gotSideEffects, for: target, in: project, by: "\(project.name)_\(target.name)")
    }

    func test_map_when_a_project_is_not_external_target_has_swift_source_and_resource_files() async throws {
        // Given
        let sources: [SourceFile] = ["/ViewController.swift"]
        let resources: [ResourceFileElement] = [.file(path: "/AbsolutePath/Project/Resources/image.png")]
        let target = Target.test(product: .staticLibrary, sources: sources, resources: .init(resources))
        project = Project.test(path: try AbsolutePath(validating: "/AbsolutePath/Project"), targets: [target], type: .local)
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // Got
        let (_, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        try verify(gotSideEffects, for: target, in: project, by: "\(project.name)_\(target.name)")
    }

    func test_map_when_a_project_is_external_target_has_swift_source_and_synthesized_files() async throws {
        // Given
        let sources: [SourceFile] = ["/ViewController.swift"]
        let resources: [ResourceFileElement] = []
        let buildableFolders: [BuildableFolder] = [.init(
            path: try AbsolutePath(validating: "/AbsolutePath"),
            exceptions: [],
            resolvedFiles: [.init(path: "/video.mov", compilerFlags: nil)]
        )]
        let target = Target.test(
            product: .staticLibrary,
            sources: sources,
            resources: .init(
                resources
            ),
            buildableFolders: buildableFolders
        )
        project = Project.test(
            path: try AbsolutePath(validating: "/AbsolutePath/Project"),
            targets: [target],
            resourceSynthesizers: [.test(extensions: ["mov"])],
            type: .external(hash: nil)
        )
        given(buildableFolderChecker).containsResources(.value(buildableFolders)).willReturn(false)
        given(buildableFolderChecker).containsSources(.value(buildableFolders)).willReturn(false)

        // Got
        let (_, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        try verify(gotSideEffects, for: target, in: project, by: "\(project.name)_\(target.name)")
    }

    func test_map_when_a_project_is_not_external_target_has_swift_source_and_synthesized_files() async throws {
        // Given
        let sources: [SourceFile] = ["/ViewController.swift"]
        let resources: [ResourceFileElement] = []
        let buildableFolders: [BuildableFolder] = [.init(
            path: try AbsolutePath(validating: "/AbsolutePath"),
            exceptions: [],
            resolvedFiles: [.init(path: "/video.mov", compilerFlags: nil)]
        )]
        let target = Target.test(
            product: .staticLibrary,
            sources: sources,
            resources: .init(resources),
            buildableFolders: buildableFolders
        )
        project = Project.test(
            path: try AbsolutePath(validating: "/AbsolutePath/Project"),
            targets: [target],
            resourceSynthesizers: [.test(extensions: ["mov"])],
            type: .local
        )
        given(buildableFolderChecker).containsResources(.value(buildableFolders)).willReturn(false)
        given(buildableFolderChecker).containsSources(.value(buildableFolders)).willReturn(false)

        // Got
        let (_, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        try verify(gotSideEffects, for: target, in: project, by: "\(project.name)_\(target.name)")
    }

    func test_map_when_a_project_is_external_target_has_objc_source_files() async throws {
        // Given
        let sources: [SourceFile] = ["/ViewController.m"]
        let resources: [ResourceFileElement] = [.file(path: "/AbsolutePath/Project/Resources/image.png")]
        let target = Target.test(product: .staticLibrary, sources: sources, resources: .init(resources))
        project = Project.test(
            path: try AbsolutePath(validating: "/AbsolutePath/Project"),
            targets: [target],
            type: .external(hash: nil)
        )
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // Got
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then
        let gotTarget = try XCTUnwrap(gotProject.targets.values.sorted().last)
        verifyObjcBundleAccessor(
            for: target,
            gotTarget: gotTarget,
            gotSideEffects: gotSideEffects
        )
    }

    func test_map_when_a_project_is_not_external_target_has_objc_source_files() async throws {
        // Given
        let sources: [SourceFile] = ["/ViewController.m"]
        let resources: [ResourceFileElement] = [.file(path: "/AbsolutePath/Project/Resources/image.png")]
        let target = Target.test(product: .staticLibrary, sources: sources, resources: .init(resources))
        project = Project.test(path: try AbsolutePath(validating: "/AbsolutePath/Project"), targets: [target], type: .local)
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // Got
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then
        let gotTarget = try XCTUnwrap(gotProject.targets.values.sorted().last)
        XCTAssertEqual(
            gotTarget.settings?.base["GCC_PREFIX_HEADER"],
            nil
        )
        XCTAssertEqual(gotTarget.sources.count, 1)
        XCTAssertEqual(gotSideEffects.count, 0)
    }

    func test_map_when_project_name_has_dashes_in_it_bundle_name_include_dash_for_project_name_and_underscore_for_target_name(
    ) async throws {
        // Given
        let projectName = "sdk-with-dash"
        let targetName = "target-with-dash"
        let expectedBundleName = "sdk-with-dash_target_with_dash"
        let sources: [SourceFile] = ["/ViewController.m", "/ViewController2.swift"]
        let resources: [ResourceFileElement] = [.file(path: "/AbsolutePath/Project/Resources/image.png")]
        let target = Target.test(name: targetName, product: .staticLibrary, sources: sources, resources: .init(resources))
        project = Project.test(path: try AbsolutePath(validating: "/AbsolutePath/Project"), name: projectName, targets: [target])
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // Got
        let (gotProject, _) = try await subject.map(project: project)
        let bundleTarget = try XCTUnwrap(gotProject.targets.values.sorted().first(where: { $0.product == .bundle }))

        // Then
        XCTAssertEqual(expectedBundleName, bundleTarget.name)
        XCTAssertEqual(expectedBundleName, bundleTarget.productName)
        XCTAssertEqual(2, gotProject.targets.count) // One code target, one bundle target
    }

    // MARK: - Verifiers

    private func verify(
        _ gotSideEffects: [SideEffectDescriptor],
        for target: Target,
        in project: Project,
        by bundleName: String
    ) throws {
        XCTAssertEqual(gotSideEffects.count, 1)
        let sideEffect = try XCTUnwrap(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            XCTFail("Expected file descriptor")
            return
        }
        let expectedPath = expectedTuistBundleSwiftFilePath(for: target)
        let expectedContents = ResourcesProjectMapper
            .fileContent(
                targetName: target.name,
                bundleName: bundleName,
                target: target,
                in: project
            )
        XCTAssertEqual(file.path, expectedPath)
        XCTAssertEqual(file.contents, expectedContents.data(using: .utf8))
    }

    private func verifyObjcBundleAccessor(
        for target: Target,
        gotTarget: Target,
        gotSideEffects: [SideEffectDescriptor]
    ) {
        XCTAssertEqual(
            gotTarget.settings?.base["GCC_PREFIX_HEADER"],
            .string(
                "$(SRCROOT)/\(Constants.DerivedDirectory.name)/\(Constants.DerivedDirectory.sources)/TuistBundle+\(target.name).h"
            )
        )
        XCTAssertEqual(gotTarget.sources.count, 2)
        XCTAssertEqual(gotSideEffects.count, 2)
        let generatedFiles = gotSideEffects.compactMap {
            if case let .file(file) = $0 {
                return file
            } else {
                return nil
            }
        }

        let expectedBasePath = project.derivedDirectoryPath(for: target)
            .appending(component: Constants.DerivedDirectory.sources)
        XCTAssertEqual(
            generatedFiles,
            [
                FileDescriptor(
                    path: expectedBasePath.appending(component: "TuistBundle+\(target.name).h"),
                    contents: ResourcesProjectMapper
                        .objcHeaderFileContent(targetName: target.name)
                        .data(using: .utf8)
                ),
                FileDescriptor(
                    path: expectedBasePath.appending(component: "TuistBundle+\(target.name).m"),
                    contents: ResourcesProjectMapper
                        .objcImplementationFileContent(
                            targetName: target.name,
                            bundleName: "\(project.name)_\(target.name)"
                        )
                        .data(using: .utf8)
                ),
            ]
        )
    }

    // MARK: - Helpers

    private func expectedTuistBundleSwiftFilePath(for target: Target) -> AbsolutePath {
        project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name.camelized.uppercasingFirst).swift")
    }
}
