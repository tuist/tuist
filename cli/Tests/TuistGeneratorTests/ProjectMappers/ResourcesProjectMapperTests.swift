import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistGenerator

private let irrelevantBundleName = ""
private func supportsResources(for target: Target) -> Bool {
    target.supportsResources && (target.product != .staticFramework || target.containsResources)
}

// swiftlint:disable:next type_body_length
struct ResourcesProjectMapperTests {
    private let contentHasher: MockContentHashing
    private let buildableFolderChecker: MockBuildableFolderChecking
    private let subject: ResourcesProjectMapper

    init() {
        contentHasher = MockContentHashing()
        buildableFolderChecker = MockBuildableFolderChecking()
        subject = ResourcesProjectMapper(contentHasher: contentHasher, buildableFolderChecker: buildableFolderChecker)

        given(contentHasher)
            .hash(Parameter<Data>.any)
            .willProduce { String(data: $0, encoding: .utf8)! }
    }

    @Test
    func mapWhenTargetHasResourcesAndDoesntSupportThem() async throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/image.png")]
        let target = Target.test(product: .staticLibrary, sources: ["/Absolute/File.swift"], resources: .init(resources))
        let project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        #expect(gotSideEffects.count == 1)
        let sideEffect = try #require(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            Issue.record("Expected file descriptor")
            return
        }
        let expectedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(
                targetName: target.name,
                bundleName: "\(project.name)_\(target.name)",
                target: target,
                in: project,
                supportsResources: supportsResources(for: target)
            )
        #expect(file.path == expectedPath)
        #expect(file.contents == expectedContents.data(using: .utf8))

        // Then: Targets
        #expect(gotProject.targets.count == 2)
        let gotTarget = try #require(gotProject.targets.values.sorted().last)
        #expect(gotTarget.name == target.name)
        #expect(gotTarget.product == target.product)
        #expect(gotTarget.resources.resources.count == 0)
        #expect(gotTarget.sources.count == 2)
        #expect(gotTarget.sources.last?.path == expectedPath)
        #expect(gotTarget.sources.last?.contentHash != nil)
        #expect(gotTarget.dependencies.count == 1)
        #expect(gotTarget.dependencies.first == TargetDependency.target(
            name: "\(project.name)_\(target.name)",
            condition: .when([.ios])
        ))

        let resourcesTarget = try #require(gotProject.targets.values.sorted().first)
        #expect(resourcesTarget.name == "\(project.name)_\(target.name)")
        #expect(resourcesTarget.product == .bundle)
        #expect(resourcesTarget.destinations == target.destinations)
        #expect(resourcesTarget.bundleId == "\(target.bundleId).generated.resources")
        #expect(resourcesTarget.deploymentTargets == target.deploymentTargets)
        #expect(resourcesTarget.filesGroup == target.filesGroup)
        #expect(resourcesTarget.resources.resources == resources)
        #expect(resourcesTarget.settings?.base == [
            "SKIP_INSTALL": "YES",
            "CODE_SIGNING_ALLOWED": "NO",
            "GENERATE_MASTER_OBJECT_FILE": "NO",
            "VERSIONING_SYSTEM": "",
        ])
    }

    @Test
    func synthesizedBundleHasTuistSynthesizedTagAndInheritsParentTags() async throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/image.png")]
        let parentTags: Set<String> = ["custom-tag", "another-tag"]
        let target = Target.test(
            product: .staticLibrary,
            sources: ["/Absolute/File.swift"],
            resources: .init(resources),
            metadata: TargetMetadata(tags: parentTags)
        )
        let project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (gotProject, _) = try await subject.map(project: project)

        // Then
        let resourcesTarget = try #require(gotProject.targets.values.first(where: { $0.product == .bundle }))
        #expect(resourcesTarget.metadata.tags.contains("tuist:synthesized"))
        #expect(resourcesTarget.metadata.tags.contains("custom-tag"))
        #expect(resourcesTarget.metadata.tags.contains("another-tag"))
        #expect(resourcesTarget.metadata.tags.count == 3)
    }

    @Test
    func mapWhenExternalObjcTargetHasResourcesAndSupportsThem() async throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/image.png")]
        let target = Target.test(product: .framework, sources: ["/Absolute/File.m"], resources: .init(resources))
        let project = Project.test(targets: [target], type: .external(hash: nil))
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then
        let gotTarget = try #require(gotProject.targets.values.sorted().last)
        verifyObjcBundleAccessor(
            for: target,
            gotTarget: gotTarget,
            gotSideEffects: gotSideEffects,
            project: project
        )
    }

    @Test
    func mapWhenExternalStaticLibraryHasResourcesGeneratesBundleTarget() async throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/image.png")]
        let target = Target.test(product: .staticLibrary, sources: ["/Absolute/File.swift"], resources: .init(resources))
        let project = Project.test(targets: [target], type: .external(hash: nil))
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (gotProject, _) = try await subject.map(project: project)

        // Then
        // External packages often use Bundle.module, so we keep a dedicated resource bundle target.
        let resourcesTarget = try #require(gotProject.targets.values.first(where: { $0.product == .bundle }))
        #expect(resourcesTarget.name == "\(project.name)_\(target.name)")
        #expect(gotProject.targets.count == 2)
    }

    @Test
    func mapWhenDisableBundleAccessorsIsTrueDoesNotGenerateAccessors() async throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/image.png")]
        let target = Target.test(product: .staticLibrary, resources: .init(resources))
        let project = Project.test(
            options: .test(
                disableBundleAccessors: true
            ),
            targets: [target]
        )
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then
        #expect(project == gotProject)
        #expect(gotSideEffects == [])
    }

    @Test
    func mapWhenNoSources() async throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/image.png")]
        let target = Target.test(product: .staticLibrary, sources: [], resources: .init(resources))
        let project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then
        #expect(gotSideEffects == [])
        #expect(gotProject.targets.count == 2)

        let gotTarget = try #require(gotProject.targets.values.sorted().last)
        #expect(gotTarget.name == target.name)
        #expect(gotTarget.product == target.product)
        #expect(gotTarget.resources.resources.count == 0)
        #expect(gotTarget.sources.count == 0)
        #expect(gotTarget.dependencies.count == 1)
        #expect(gotTarget.dependencies.first == TargetDependency.target(
            name: "\(project.name)_\(target.name)",
            condition: .when([.ios])
        ))

        let resourcesTarget = try #require(gotProject.targets.values.sorted().first)
        #expect(resourcesTarget.name == "\(project.name)_\(target.name)")
        #expect(resourcesTarget.product == .bundle)
        #expect(resourcesTarget.destinations == target.destinations)
        #expect(resourcesTarget.bundleId == "\(target.bundleId).generated.resources")
        #expect(resourcesTarget.deploymentTargets == target.deploymentTargets)
        #expect(resourcesTarget.filesGroup == target.filesGroup)
        #expect(resourcesTarget.resources.resources == resources)
    }

    @Test
    func mapWhenNoSourcesButBuildableFolders() async throws {
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
        let project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value(buildableFolders)).willReturn(true)
        given(buildableFolderChecker).containsSources(.value(buildableFolders)).willReturn(true)

        // When
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        #expect(gotSideEffects.count == 1)
        let sideEffect = try #require(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            Issue.record("Expected file descriptor")
            return
        }
        let expectedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(
                targetName: target.name,
                bundleName: "\(project.name)_\(target.name)",
                target: target,
                in: project,
                supportsResources: supportsResources(for: target)
            )
        #expect(file.path == expectedPath)
        #expect(file.contents == expectedContents.data(using: .utf8))

        let gotTarget = try #require(gotProject.targets.values.sorted().last)
        #expect(gotTarget.name == target.name)
        #expect(gotTarget.product == target.product)
        #expect(gotTarget.resources.resources.count == 0)
        #expect(gotTarget.sources.count == 1)
        #expect(gotTarget.dependencies.count == 1)
        #expect(gotTarget.dependencies.first == TargetDependency.target(
            name: "\(project.name)_\(target.name)",
            condition: .when([.ios])
        ))

        let resourcesTarget = try #require(gotProject.targets.values.sorted().first)
        #expect(resourcesTarget.name == "\(project.name)_\(target.name)")
        #expect(resourcesTarget.product == .bundle)
        #expect(resourcesTarget.destinations == target.destinations)
        #expect(resourcesTarget.bundleId == "\(target.bundleId).generated.resources")
        #expect(resourcesTarget.deploymentTargets == target.deploymentTargets)
        #expect(resourcesTarget.filesGroup == target.filesGroup)
        #expect(resourcesTarget.resources.resources == resources)
    }

    @Test
    func mapWhenNoSourcesAndResourcesButBuildableFolders() async throws {
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
        let project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value(buildableFolders)).willReturn(true)
        given(buildableFolderChecker).containsSources(.value(buildableFolders)).willReturn(true)

        // When
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        #expect(gotSideEffects.count == 1)
        let sideEffect = try #require(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            Issue.record("Expected file descriptor")
            return
        }
        let expectedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(
                targetName: target.name,
                bundleName: "\(project.name)_\(target.name)",
                target: target,
                in: project,
                supportsResources: supportsResources(for: target)
            )
        #expect(file.path == expectedPath)
        #expect(file.contents == expectedContents.data(using: .utf8))

        let gotTarget = try #require(gotProject.targets.values.sorted().last)
        #expect(gotTarget.name == target.name)
        #expect(gotTarget.product == target.product)
        #expect(gotTarget.resources.resources.count == 0)
        #expect(gotTarget.sources.count == 1)
        #expect(gotTarget.dependencies.count == 1)
        #expect(gotTarget.dependencies.first == TargetDependency.target(
            name: "\(project.name)_\(target.name)",
            condition: .when([.ios])
        ))

        let resourcesTarget = try #require(gotProject.targets.values.sorted().first)
        #expect(resourcesTarget.name == "\(project.name)_\(target.name)")
        #expect(resourcesTarget.product == .bundle)
        #expect(resourcesTarget.destinations == target.destinations)
        #expect(resourcesTarget.bundleId == "\(target.bundleId).generated.resources")
        #expect(resourcesTarget.deploymentTargets == target.deploymentTargets)
        #expect(resourcesTarget.filesGroup == target.filesGroup)
        #expect(resourcesTarget.buildableFolders == [buildableFolders[1]])
        #expect(gotTarget.buildableFolders == [buildableFolders[0]])
    }

    @Test
    func mapWhenBuildableFolderContainsSourcesAndResources() async throws {
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
        let project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([buildableFolder])).willReturn(true)
        given(buildableFolderChecker).containsSources(.value([buildableFolder])).willReturn(true)

        // When
        let (gotProject, _) = try await subject.map(project: project)

        // Then
        #expect(gotProject.targets.count == 1)
        #expect(gotProject.targets.values.first(where: { $0.product == .bundle }) == nil)
        let gotTarget = try #require(gotProject.targets.values.first)
        #expect(gotTarget.buildableFolders == [buildableFolder])
    }

    @Test
    // swiftlint:disable:next function_body_length
    func mapWhenNestedBuildableFoldersShareSourcesAndResources() async throws {
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
        let project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value(buildableFolders)).willReturn(true)
        given(buildableFolderChecker).containsSources(.value(buildableFolders)).willReturn(true)

        // When
        let (gotProject, _) = try await subject.map(project: project)

        // Then
        #expect(gotProject.targets.count == 1)
        #expect(gotProject.targets.values.first(where: { $0.product == .bundle }) == nil)
        let gotTarget = try #require(gotProject.targets.values.first)
        #expect(gotTarget.buildableFolders == buildableFolders)
    }

    @Test
    func mapWhenTargetHasCoreDataModelsAndDoesntSupportThem() async throws {
        // Given
        let coreDataModels: [CoreDataModel] =
            [CoreDataModel(path: "/data.xcdatamodeld", versions: ["/data.xcdatamodeld"], currentVersion: "1")]
        let target = Target.test(product: .staticLibrary, sources: ["/Absolute/File.swift"], coreDataModels: coreDataModels)
        let project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        #expect(gotSideEffects.count == 1)
        let sideEffect = try #require(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            Issue.record("Expected file descriptor")
            return
        }
        let expectedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(
                targetName: target.name,
                bundleName: "\(project.name)_\(target.name)",
                target: target,
                in: project,
                supportsResources: supportsResources(for: target)
            )
        #expect(file.path == expectedPath)
        #expect(file.contents == expectedContents.data(using: .utf8))

        // Then: Targets
        #expect(gotProject.targets.count == 2)
        let gotTarget = try #require(gotProject.targets.values.sorted().last)
        #expect(gotTarget.name == target.name)
        #expect(gotTarget.product == target.product)
        #expect(gotTarget.resources.resources.count == 0)
        #expect(gotTarget.sources.count == 2)
        #expect(gotTarget.sources.last?.path == expectedPath)
        #expect(gotTarget.sources.last?.contentHash != nil)
        #expect(gotTarget.dependencies.count == 1)
        #expect(gotTarget.dependencies.first == TargetDependency.target(
            name: "\(project.name)_\(target.name)",
            condition: .when([.ios])
        ))

        let resourcesTarget = try #require(gotProject.targets.values.sorted().first)
        #expect(resourcesTarget.name == "\(project.name)_\(target.name)")
        #expect(resourcesTarget.product == .bundle)
        #expect(resourcesTarget.destinations == target.destinations)
        #expect(resourcesTarget.bundleId == "\(target.bundleId).generated.resources")
        #expect(resourcesTarget.deploymentTargets == target.deploymentTargets)
        #expect(resourcesTarget.filesGroup == target.filesGroup)
        #expect(resourcesTarget.coreDataModels == coreDataModels)
    }

    @Test
    func mapWhenTargetHasResourcesAndSupportsThem() async throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/image.png")]
        let target = Target.test(product: .framework, sources: ["/Absolute/File.swift"], resources: .init(resources))
        let project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        #expect(gotSideEffects.count == 1)
        let sideEffect = try #require(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            Issue.record("Expected file descriptor")
            return
        }
        let expectedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(
                targetName: target.name,
                bundleName: irrelevantBundleName,
                target: target,
                in: project,
                supportsResources: supportsResources(for: target)
            )
        #expect(file.path == expectedPath)
        #expect(file.contents == expectedContents.data(using: .utf8))

        // Then: Targets
        #expect(gotProject.targets.count == 1)
        let gotTarget = try #require(gotProject.targets.values.sorted().first)
        #expect(gotTarget.name == target.name)
        #expect(gotTarget.product == target.product)
        #expect(gotTarget.resources.resources == resources)
        #expect(gotTarget.sources.count == 2)
        #expect(gotTarget.sources.last?.path == expectedPath)
        #expect(gotTarget.sources.last?.contentHash != nil)
        #expect(gotTarget.dependencies.count == 0)
    }

    @Test
    func mapWhenStaticFrameworkHasResourcesAndSupportsThem() async throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/image.png")]
        let target = Target.test(product: .staticFramework, sources: ["/Absolute/File.swift"], resources: .init(resources))
        let project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        #expect(gotSideEffects.count == 1)
        let sideEffect = try #require(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            Issue.record("Expected file descriptor")
            return
        }
        let expectedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(
                targetName: target.name,
                bundleName: "\(project.name)_\(target.name)",
                target: target,
                in: project,
                supportsResources: true
            )
        #expect(file.path == expectedPath)
        #expect(file.contents == expectedContents.data(using: .utf8))

        // Then: Targets
        #expect(gotProject.targets.count == 1)
        let gotTarget = try #require(gotProject.targets.values.sorted().first)
        #expect(gotTarget.name == target.name)
        #expect(gotTarget.product == target.product)
        #expect(gotTarget.resources.resources == resources)
        #expect(gotTarget.sources.count == 2)
        #expect(gotTarget.sources.last?.path == expectedPath)
        #expect(gotTarget.sources.last?.contentHash != nil)
        #expect(gotTarget.dependencies.count == 0)
    }

    @Test
    func mapWhenTargetHasNoResourcesButHasMetalSourceFilesAndSupportsThem() async throws {
        // Given
        let target = Target.test(
            product: .framework,
            sources: ["/Absolute/File.swift", "/Absolute/File.metal"],
            resources: .init([])
        )
        let project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        #expect(gotSideEffects.count == 1)
        let sideEffect = try #require(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            Issue.record("Expected file descriptor")
            return
        }
        let expectedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(
                targetName: target.name,
                bundleName: irrelevantBundleName,
                target: target,
                in: project,
                supportsResources: supportsResources(for: target)
            )
        #expect(file.path == expectedPath)
        #expect(file.contents == expectedContents.data(using: .utf8))

        // Then: Targets
        #expect(gotProject.targets.count == 1)
        let gotTarget = try #require(gotProject.targets.values.sorted().first)
        #expect(gotTarget.name == target.name)
        #expect(gotTarget.product == target.product)
        #expect(gotTarget.sources.count == 3)
        #expect(gotTarget.sources.last?.path == expectedPath)
        #expect(gotTarget.sources.last?.contentHash != nil)
        #expect(gotTarget.dependencies.count == 0)
    }

    @Test
    func mapWhenTargetHasCoreDataModelsAndSupportsThem() async throws {
        // Given
        let coreDataModels: [CoreDataModel] =
            [CoreDataModel(path: "/data.xcdatamodeld", versions: ["/data.xcdatamodeld"], currentVersion: "1")]
        let target = Target.test(product: .framework, sources: ["/Absolute/File.swift"], coreDataModels: coreDataModels)
        let project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        #expect(gotSideEffects.count == 1)
        let sideEffect = try #require(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            Issue.record("Expected file descriptor")
            return
        }
        let expectedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(
                targetName: target.name,
                bundleName: irrelevantBundleName,
                target: target,
                in: project,
                supportsResources: supportsResources(for: target)
            )
        #expect(file.path == expectedPath)
        #expect(file.contents == expectedContents.data(using: .utf8))

        // Then: Targets
        #expect(gotProject.targets.count == 1)
        let gotTarget = try #require(gotProject.targets.values.sorted().first)
        #expect(gotTarget.name == target.name)
        #expect(gotTarget.product == target.product)
        #expect(gotTarget.coreDataModels == coreDataModels)
        #expect(gotTarget.sources.count == 2)
        #expect(gotTarget.sources.last?.path == expectedPath)
        #expect(gotTarget.sources.last?.contentHash != nil)
        #expect(gotTarget.dependencies.count == 0)
    }

    @Test
    func mapWhenTargetHasNoResources() async throws {
        // Given
        let resources: [ResourceFileElement] = []
        let target = Target.test(product: .framework, resources: .init(resources))
        let project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then
        #expect(Array(gotProject.targets.values) == [target])
        #expect(gotSideEffects.isEmpty)
    }

    @Test
    func mapWhenTargetDoesNotSupportSources() async throws {
        // Given
        let resources: [ResourceFileElement] = [
            .file(path: "/Some/ResourceA"),
            .file(path: "/Some/ResourceB"),
        ]
        let target = Target.test(product: .bundle, resources: .init(resources))
        let project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then
        #expect(Array(gotProject.targets.values) == [target])
        #expect(gotSideEffects.isEmpty)
    }

    @Test
    func mapWhenTargetHasNameWithHyphen() async throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/image.png")]
        let target = Target.test(
            name: "test-tuist",
            product: .staticLibrary,
            sources: ["/Absolute/File.swift"],
            resources: .init(resources)
        )
        let project = Project.test(targets: [target])
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (_, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        #expect(gotSideEffects.count == 1)
        let sideEffect = try #require(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            Issue.record("Expected file descriptor")
            return
        }
        let expectedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name.camelized.uppercasingFirst).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(
                targetName: target.name,
                bundleName: "\(project.name)_test_tuist",
                target: target,
                in: project,
                supportsResources: supportsResources(for: target)
            )
        #expect(file.path == expectedPath)
        #expect(file.contents == expectedContents.data(using: .utf8))
    }

    @Test
    func mapWhenProjectIsExternalTargetHasSwiftSourceButNoResourceFiles() async throws {
        // Given
        let sources: [SourceFile] = ["/ViewController.swift"]
        let resources: [ResourceFileElement] = []
        let target = Target.test(product: .staticLibrary, sources: sources, resources: .init(resources))
        let project = Project.test(
            path: try AbsolutePath(validating: "/AbsolutePath/Project"),
            targets: [target],
            type: .external(hash: nil)
        )
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then
        #expect(Array(gotProject.targets.values) == [target])
        #expect(gotSideEffects.isEmpty)
    }

    @Test
    func mapWhenProjectIsNotExternalTargetHasSwiftSourceButNoResourceFiles() async throws {
        // Given
        let sources: [SourceFile] = ["/ViewController.swift"]
        let resources: [ResourceFileElement] = []
        let target = Target.test(product: .staticLibrary, sources: sources, resources: .init(resources))
        let project = Project.test(path: try AbsolutePath(validating: "/AbsolutePath/Project"), targets: [target], type: .local)
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then
        #expect(Array(gotProject.targets.values) == [target])
        #expect(gotSideEffects.isEmpty)
    }

    @Test
    func mapWhenProjectIsExternalTargetHasSwiftSourceAndResourceFiles() async throws {
        // Given
        let sources: [SourceFile] = ["/ViewController.swift"]
        let resources: [ResourceFileElement] = [.file(path: "/AbsolutePath/Project/Resources/image.png")]
        let target = Target.test(product: .staticLibrary, sources: sources, resources: .init(resources))
        let project = Project.test(
            path: try AbsolutePath(validating: "/AbsolutePath/Project"),
            targets: [target],
            type: .external(hash: nil)
        )
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (_, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        try verifySideEffects(gotSideEffects, for: target, in: project, bundleName: "\(project.name)_\(target.name)")
    }

    @Test
    func mapWhenProjectIsExternalStaticFrameworkHasResourcesUsesStaticFrameworkAccessor() async throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/AbsolutePath/Project/Resources/image.png")]
        let target = Target.test(product: .staticFramework, sources: ["/ViewController.swift"], resources: .init(resources))
        let project = Project.test(
            path: try AbsolutePath(validating: "/AbsolutePath/Project"),
            targets: [target],
            type: .external(hash: nil)
        )
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (_, gotSideEffects) = try await subject.map(project: project)

        // Then
        let sideEffect = try #require(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            Issue.record("Expected file descriptor")
            return
        }
        let contents = String(data: file.contents ?? Data(), encoding: .utf8) ?? ""
        // External static frameworks keep SwiftPM-style accessors to locate the resource bundle.
        #expect(contents.contains("Swift Bundle Accessor for Static Frameworks"))
        #expect(contents.contains("static let module"))
        #expect(!contents.contains("public final class"))
    }

    @Test
    func mapWhenProjectIsNotExternalTargetHasSwiftSourceAndResourceFiles() async throws {
        // Given
        let sources: [SourceFile] = ["/ViewController.swift"]
        let resources: [ResourceFileElement] = [.file(path: "/AbsolutePath/Project/Resources/image.png")]
        let target = Target.test(product: .staticLibrary, sources: sources, resources: .init(resources))
        let project = Project.test(path: try AbsolutePath(validating: "/AbsolutePath/Project"), targets: [target], type: .local)
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (_, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        try verifySideEffects(gotSideEffects, for: target, in: project, bundleName: "\(project.name)_\(target.name)")
    }

    @Test(arguments: [
        ("/ViewController.swift", true),
        ("/TargetResources.swift", false)
    ])
    func mapWhenProjectIsNotExternalTargetHasTargetResourcesSwiftSourceAndResourceFiles(
        sourceFile: SourceFile,
        expectsPublicImport: Bool
    ) async throws {
        // Given
        let sources: [SourceFile] = [sourceFile]
        let resources: [ResourceFileElement] = [.file(path: "/AbsolutePath/Project/Resources/image.png")]
        let target = Target.test(name: "Target", product: .staticLibrary, sources: sources, resources: .init(resources))
        let project = Project.test(path: try AbsolutePath(validating: "/AbsolutePath/Project"), targets: [target], type: .local)
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (_, gotSideEffects) = try await subject.map(project: project)

        // Then: Side effects
        try verifySideEffects(gotSideEffects, for: target, in: project, bundleName: "\(project.name)_\(target.name)") { file in
            #expect(file.contents?.contains("public import Foundation".data(using: .utf8)!) == expectsPublicImport)
        }
    }

    @Test
    func mapWhenProjectIsExternalTargetHasObjcSourceFiles() async throws {
        // Given
        let sources: [SourceFile] = ["/ViewController.m"]
        let resources: [ResourceFileElement] = [.file(path: "/AbsolutePath/Project/Resources/image.png")]
        let target = Target.test(product: .staticLibrary, sources: sources, resources: .init(resources))
        let project = Project.test(
            path: try AbsolutePath(validating: "/AbsolutePath/Project"),
            targets: [target],
            type: .external(hash: nil)
        )
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then
        let gotTarget = try #require(gotProject.targets.values.sorted().last)
        verifyObjcBundleAccessor(
            for: target,
            gotTarget: gotTarget,
            gotSideEffects: gotSideEffects,
            project: project
        )
    }

    @Test
    func mapWhenProjectIsLocalStaticFramework_excludesInfoPlistFromSources() async throws {
        // Given
        let resources: [ResourceFileElement] = [.file(path: "/AbsolutePath/Project/Resources/image.png")]
        let targetSettings = Settings(
            base: ["EXCLUDED_SOURCE_FILE_NAMES": SettingValue.string("Custom.plist")],
            baseDebug: [:],
            configurations: Settings.default.configurations
        )
        let target = Target.test(
            name: "StaticResourcesFramework",
            product: .staticFramework,
            settings: targetSettings,
            resources: .init(resources)
        )
        let project = Project.test(
            path: try AbsolutePath(validating: "/AbsolutePath/Project"),
            targets: [target],
            type: .local
        )
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (gotProject, _) = try await subject.map(project: project)

        // Then
        let gotTarget = try #require(gotProject.targets[target.name])
        #expect(gotTarget.settings?.base["EXCLUDED_SOURCE_FILE_NAMES"] ==
            SettingValue.array(["$(inherited)", "Custom.plist", "Info.plist"]))
    }

    @Test
    func mapWhenProjectIsNotExternalTargetHasObjcSourceFiles() async throws {
        // Given
        let sources: [SourceFile] = ["/ViewController.m"]
        let resources: [ResourceFileElement] = [.file(path: "/AbsolutePath/Project/Resources/image.png")]
        let target = Target.test(product: .staticLibrary, sources: sources, resources: .init(resources))
        let project = Project.test(path: try AbsolutePath(validating: "/AbsolutePath/Project"), targets: [target], type: .local)
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (gotProject, gotSideEffects) = try await subject.map(project: project)

        // Then
        let gotTarget = try #require(gotProject.targets.values.sorted().last)
        #expect(gotTarget.settings?.base["GCC_PREFIX_HEADER"] == nil)
        #expect(gotTarget.sources.count == 1)
        #expect(gotSideEffects.count == 0)
    }

    @Test
    func mapWhenProjectNameHasDashesInItBundleNameIncludeDashForProjectNameAndUnderscoreForTargetName() async throws {
        // Given
        let projectName = "sdk-with-dash"
        let targetName = "target-with-dash"
        let expectedBundleName = "sdk-with-dash_target_with_dash"
        let sources: [SourceFile] = ["/ViewController.m", "/ViewController2.swift"]
        let resources: [ResourceFileElement] = [.file(path: "/AbsolutePath/Project/Resources/image.png")]
        let target = Target.test(name: targetName, product: .staticLibrary, sources: sources, resources: .init(resources))
        let project = Project.test(
            path: try AbsolutePath(validating: "/AbsolutePath/Project"),
            name: projectName,
            targets: [target]
        )
        given(buildableFolderChecker).containsResources(.value([])).willReturn(false)
        given(buildableFolderChecker).containsSources(.value([])).willReturn(false)

        // When
        let (gotProject, _) = try await subject.map(project: project)
        let bundleTarget = try #require(gotProject.targets.values.sorted().first(where: { $0.product == .bundle }))

        // Then
        #expect(bundleTarget.name == expectedBundleName)
        #expect(bundleTarget.productName == expectedBundleName)
        #expect(gotProject.targets.count == 2)
    }

    // MARK: - Helpers

    private func verifySideEffects(
        _ gotSideEffects: [SideEffectDescriptor],
        for target: Target,
        in project: Project,
        bundleName: String,
        additionalFileExpectations: ((FileDescriptor) -> Void)? = nil
    ) throws {
        #expect(gotSideEffects.count == 1)
        let sideEffect = try #require(gotSideEffects.first)
        guard case let SideEffectDescriptor.file(file) = sideEffect else {
            Issue.record("Expected file descriptor")
            return
        }
        let expectedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "TuistBundle+\(target.name.camelized.uppercasingFirst).swift")
        let expectedContents = ResourcesProjectMapper
            .fileContent(
                targetName: target.name,
                bundleName: bundleName,
                target: target,
                in: project,
                supportsResources: supportsResources(for: target)
            )
        #expect(file.path == expectedPath)
        #expect(file.contents == expectedContents.data(using: .utf8))
        if let additionalFileExpectations {
            additionalFileExpectations(file)
        }
    }

    private func verifyObjcBundleAccessor(
        for target: Target,
        gotTarget: Target,
        gotSideEffects: [SideEffectDescriptor],
        project: Project
    ) {
        #expect(
            gotTarget.settings?.base["GCC_PREFIX_HEADER"] ==
                .string(
                    "$(SRCROOT)/\(Constants.DerivedDirectory.name)/\(Constants.DerivedDirectory.sources)/TuistBundle+\(target.name).h"
                )
        )
        #expect(gotTarget.sources.count == 2)
        #expect(gotSideEffects.count == 2)
        let generatedFiles = gotSideEffects.compactMap {
            if case let .file(file) = $0 {
                return file
            } else {
                return nil
            }
        }

        let expectedBasePath = project.derivedDirectoryPath(for: target)
            .appending(component: Constants.DerivedDirectory.sources)
        #expect(
            generatedFiles == [
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
}
