import FileSystem
import Foundation
import Mockable
import Path
import struct ProjectDescription.Project
import enum ProjectDescription.TargetDependency
import Synchronization
import Testing
import TSCBasic
import TuistConstants
import TuistCore
import TuistNooraTesting
import TuistSupport
import TuistTesting
import XcodeGraph
@testable import TuistLoader

private final class SwiftPackageManagerLockObservation: Sendable {
    private struct State {
        var heldDuringLoadPackage = false
        var loadPackageCallCount = 0
    }

    private let state = Mutex(State())

    var heldDuringLoadPackage: Bool { state.withLock { $0.heldDuringLoadPackage } }
    var loadPackageCallCount: Int { state.withLock { $0.loadPackageCallCount } }

    func record(lockHeld: Bool) {
        state.withLock {
            $0.loadPackageCallCount += 1
            if lockHeld { $0.heldDuringLoadPackage = true }
        }
    }
}

private struct CapturedPackagePrebuilt: Equatable {
    let path: String
    let checkoutPath: String?
    let includePaths: [String]?
}

private final class PackageInfoMapperPrebuiltSpy: PackageInfoMapping, @unchecked Sendable {
    private struct State {
        var mapCallCount = 0
        var capturedPrebuilt: CapturedPackagePrebuilt?
    }

    private let packageIdentity: String
    private let productName: String
    private let state = Mutex(State())

    init(packageIdentity: String, productName: String) {
        self.packageIdentity = packageIdentity
        self.productName = productName
    }

    var mapCallCount: Int {
        state.withLock(\.mapCallCount)
    }

    var capturedPrebuilt: CapturedPackagePrebuilt? {
        state.withLock(\.capturedPrebuilt)
    }

    func resolveExternalDependencies(
        path _: Path.AbsolutePath,
        packagePath _: Path.AbsolutePath?,
        packageInfos _: [String: PackageInfo],
        packageToFolder _: [String: Path.AbsolutePath],
        packageToTargetsToArtifactPaths _: [String: [String: Path.AbsolutePath]],
        packageModuleAliases _: [String: [String: String]],
        packageSettings _: TuistCore.PackageSettings
    ) async throws -> [String: [ProjectDescription.TargetDependency]] {
        [:]
    }

    func map(
        packageInfo: PackageInfo,
        path _: Path.AbsolutePath,
        packageType: PackageType,
        packageSettings _: TuistCore.PackageSettings,
        packageModuleAliases _: [String: [String: String]],
        enabledTraits _: Set<String>
    ) async throws -> ProjectDescription.Project? {
        let capturedPrebuilt: CapturedPackagePrebuilt?
        if case let .external(
            origin: .remote,
            artifactPaths: _,
            packagePrebuilts: packagePrebuilts,
            derivedXCFrameworksPath: _
        ) = packageType,
            let prebuilt = packagePrebuilts[packageIdentity]?[productName]
        {
            capturedPrebuilt = CapturedPackagePrebuilt(
                path: prebuilt.path.pathString,
                checkoutPath: prebuilt.checkoutPath?.pathString,
                includePaths: prebuilt.includePath?.map(\.pathString)
            )
        } else {
            capturedPrebuilt = nil
        }

        state.withLock {
            $0.mapCallCount += 1
            $0.capturedPrebuilt = capturedPrebuilt
        }

        return ProjectDescription.Project(name: packageInfo.name, targets: [])
    }
}

struct SwiftPackageManagerGraphLoaderTests {
    private let swiftPackageManagerController = MockSwiftPackageManagerControlling()
    private let packageInfoMapper = MockPackageInfoMapping()
    private let manifestLoader = MockManifestLoading()
    private let fileSystem = FileSystem()
    private let contentHasher = MockContentHashing()
    private let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
    private let subject: SwiftPackageManagerGraphLoader

    init() {
        // An unavailable cache directory disables the graph cache, keeping the tests that
        // don't exercise caching hermetic.
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .any)
            .willThrow(TestError("The graph cache is disabled in tests"))
        subject = SwiftPackageManagerGraphLoader(
            swiftPackageManagerController: swiftPackageManagerController,
            packageInfoMapper: packageInfoMapper,
            manifestLoader: manifestLoader,
            fileSystem: fileSystem,
            contentHasher: contentHasher,
            cacheDirectoriesProvider: cacheDirectoriesProvider
        )

        given(contentHasher)
            .hash(Parameter<[String]>.any)
            .willProduce { $0.joined(separator: "-") }
        given(manifestLoader)
            .loadPackage(at: .any, disableSandbox: .value(true))
            .willReturn(.test())
        given(packageInfoMapper)
            .map(
                packageInfo: .any,
                path: .any,
                packageType: .any,
                packageSettings: .any,
                packageModuleAliases: .any,
                enabledTraits: .any
            )
            .willReturn(.test())
    }

    @Test
    func test_load() async throws {
        try await withMockedDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
                temporaryDirectory in
                // Given
                let packageSettings = PackageSettings.test()

                let workspacePath = temporaryDirectory.appending(components: [
                    ".build", "workspace-state.json",
                ])
                try await fileSystem.makeDirectory(at: workspacePath.parentDirectory)
                try await fileSystem.writeText(
                    """
                    {
                      "object" : {
                        "artifacts" : [],
                        "dependencies" : [
                          {
                            "basedOn" : null,
                            "packageRef" : {
                              "identity" : "Alamofire.Alamofire",
                              "kind" : "registry",
                              "location" : "Alamofire.Alamofire",
                              "name" : "Alamofire.Alamofire"
                            },
                            "state" : {
                              "name" : "registryDownload",
                              "version" : "5.10.2"
                            },
                            "subpath" : "Alamofire/Alamofire/5.10.2"
                          }
                        ],
                      }
                    }
                    """,
                    at: workspacePath
                )

                try await fileSystem.makeDirectory(
                    at: temporaryDirectory.appending(components: [".build", "Derived"])
                )
                try await fileSystem.touch(
                    temporaryDirectory.appending(components: [
                        ".build", "Derived", "Package.resolved",
                    ])
                )
                try await fileSystem.touch(
                    temporaryDirectory.appending(component: "Package.resolved")
                )

                given(packageInfoMapper)
                    .resolveExternalDependencies(
                        path: .any,
                        packagePath: .any,
                        packageInfos: .any,
                        packageToFolder: .any,
                        packageToTargetsToArtifactPaths: .any,
                        packageModuleAliases: .any,
                        packageSettings: .any
                    )
                    .willReturn([:])

                // When
                let (got, lintingIssues) = try await subject.load(
                    packagePath: temporaryDirectory.appending(component: "Package.swift"),
                    packageSettings: packageSettings,
                    disableSandbox: true
                )

                // Then
                #expect(
                    got.externalProjects.values.map(\.hash) == [
                        "Alamofire.Alamofire-5.10.2",
                    ]
                )
                #expect(
                    lintingIssues.isEmpty
                )
            }
        }
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func load_doesNotHoldSwiftPackageManagerLock_whenLoadingManifests() async throws {
        // The Swift package manager scratch-directory lock is acquired by every
        // `swift package` subprocess. Holding the lock around manifest-loading
        // subprocesses deadlocks the parent and child on the same lock file
        // (https://github.com/tuist/tuist/issues/10754).
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let scratchDirectory = temporaryDirectory.appending(component: ".build")

        // Given
        let packageSettings = PackageSettings.test()
        let workspacePath = scratchDirectory.appending(component: "workspace-state.json")
        try await fileSystem.makeDirectory(at: workspacePath.parentDirectory)
        try await fileSystem.writeText(
            #"{ "object" : { "artifacts" : [], "dependencies" : [] } }"#,
            at: workspacePath
        )
        try await fileSystem.makeDirectory(at: scratchDirectory.appending(component: "Derived"))
        try await fileSystem.touch(scratchDirectory.appending(components: "Derived", "Package.resolved"))
        try await fileSystem.touch(temporaryDirectory.appending(component: "Package.resolved"))

        let lockObservation = SwiftPackageManagerLockObservation()
        let manifestLoader = MockManifestLoading()
        given(manifestLoader)
            .loadPackage(at: .any, disableSandbox: .any)
            .willProduce { _, _ in
                let probe = try TSCBasic.FileLock.prepareLock(
                    fileToLock: try TSCBasic.AbsolutePath(validating: scratchDirectory.pathString)
                )
                let lockWasHeld: Bool
                do {
                    try probe.lock(type: .exclusive, blocking: false)
                    probe.unlock()
                    lockWasHeld = false
                } catch {
                    lockWasHeld = true
                }
                lockObservation.record(lockHeld: lockWasHeld)
                return .test()
            }
        let packageInfoMapper = MockPackageInfoMapping()
        given(packageInfoMapper)
            .resolveExternalDependencies(
                path: .any,
                packagePath: .any,
                packageInfos: .any,
                packageToFolder: .any,
                packageToTargetsToArtifactPaths: .any,
                packageModuleAliases: .any,
                packageSettings: .any
            )
            .willReturn([:])
        let subject = SwiftPackageManagerGraphLoader(
            swiftPackageManagerController: swiftPackageManagerController,
            packageInfoMapper: packageInfoMapper,
            manifestLoader: manifestLoader,
            fileSystem: fileSystem,
            contentHasher: contentHasher,
            cacheDirectoriesProvider: cacheDirectoriesProvider
        )

        // When
        _ = try await subject.load(
            packagePath: temporaryDirectory.appending(component: "Package.swift"),
            packageSettings: packageSettings,
            disableSandbox: true
        )

        // Then
        #expect(lockObservation.loadPackageCallCount > 0)
        #expect(lockObservation.heldDuringLoadPackage == false)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func load_when_scratchPathArgumentIsPresent_readsStateFromScratchDirectory() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let scratchDirectory = temporaryDirectory.appending(component: "custom-build")

        // Given
        let packageSettings = PackageSettings.test()

        let workspacePath = scratchDirectory.appending(component: "workspace-state.json")
        try await fileSystem.makeDirectory(at: workspacePath.parentDirectory)
        try await fileSystem.writeText(
            """
            {
              "object" : {
                "artifacts" : [],
                "dependencies" : [
                  {
                    "basedOn" : null,
                    "packageRef" : {
                      "identity" : "Alamofire.Alamofire",
                      "kind" : "registry",
                      "location" : "Alamofire.Alamofire",
                      "name" : "Alamofire.Alamofire"
                    },
                    "state" : {
                      "name" : "registryDownload",
                      "version" : "5.10.2"
                    },
                    "subpath" : "Alamofire/Alamofire/5.10.2"
                  }
                ],
              }
            }
            """,
            at: workspacePath
        )

        try await fileSystem.makeDirectory(at: scratchDirectory.appending(component: "Derived"))
        try await fileSystem.touch(
            scratchDirectory.appending(components: [
                "Derived", "Package.resolved",
            ])
        )
        try await fileSystem.touch(
            temporaryDirectory.appending(component: "Package.resolved")
        )

        given(packageInfoMapper)
            .resolveExternalDependencies(
                path: .any,
                packagePath: .any,
                packageInfos: .any,
                packageToFolder: .any,
                packageToTargetsToArtifactPaths: .any,
                packageModuleAliases: .any,
                packageSettings: .any
            )
            .willReturn([:])

        // When
        let (got, lintingIssues) = try await subject.load(
            packagePath: temporaryDirectory.appending(component: "Package.swift"),
            packageSettings: packageSettings,
            disableSandbox: true,
            swiftPackageManagerArguments: ["--scratch-path", scratchDirectory.pathString]
        )

        // Then
        #expect(
            got.externalProjects.values.map(\.hash) == [
                "Alamofire.Alamofire-5.10.2",
            ]
        )
        #expect(lintingIssues.isEmpty)
        verify(packageInfoMapper)
            .resolveExternalDependencies(
                path: .value(scratchDirectory),
                packagePath: .value(temporaryDirectory),
                packageInfos: .any,
                packageToFolder: .any,
                packageToTargetsToArtifactPaths: .any,
                packageModuleAliases: .any,
                packageSettings: .any
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func load_when_swifterPMPackageInfoCacheIsFresh_usesCachedPackageInfo() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let scratchDirectory = temporaryDirectory.appending(component: ".build")
        let packagePath = temporaryDirectory.appending(component: "Package.swift")
        let dependencyPackagePath = scratchDirectory.appending(
            components: "registry", "downloads", "Alamofire", "Alamofire", "5.10.2"
        )

        try await writeRegistryWorkspaceState(
            scratchDirectory: scratchDirectory,
            dependencySubpath: "Alamofire/Alamofire/5.10.2"
        )
        try await writeSwiftPackageManifest(at: temporaryDirectory)
        try await writeSwiftPackageManifest(at: dependencyPackagePath)
        try await writeSwifterPMPackageInfoCache(
            scratchDirectory: scratchDirectory,
            rootPackagePath: temporaryDirectory,
            dependencyPackagePath: dependencyPackagePath
        )

        given(packageInfoMapper)
            .resolveExternalDependencies(
                path: .any,
                packagePath: .any,
                packageInfos: .any,
                packageToFolder: .any,
                packageToTargetsToArtifactPaths: .any,
                packageModuleAliases: .any,
                packageSettings: .any
            )
            .willReturn([:])

        // When
        _ = try await subject.load(
            packagePath: packagePath,
            packageSettings: .test(),
            disableSandbox: true
        )

        // Then
        verify(manifestLoader)
            .loadPackage(at: .any, disableSandbox: .any)
            .called(0)
        verify(packageInfoMapper)
            .map(
                packageInfo: .value(.alamofire),
                path: .value(dependencyPackagePath),
                packageType: .any,
                packageSettings: .any,
                packageModuleAliases: .any,
                enabledTraits: .any
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func load_when_registryPackageInfoCacheHasNoManifest_usesCachedPackageInfo() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let scratchDirectory = temporaryDirectory.appending(component: ".build")
        let packagePath = temporaryDirectory.appending(component: "Package.swift")
        let dependencyPackagePath = scratchDirectory.appending(
            components: "registry", "downloads", "Alamofire", "Alamofire", "5.10.2"
        )

        try await writeRegistryWorkspaceState(
            scratchDirectory: scratchDirectory,
            dependencySubpath: "Alamofire/Alamofire/5.10.2"
        )
        try await writeSwiftPackageManifest(at: temporaryDirectory)
        try await fileSystem.makeDirectory(at: dependencyPackagePath)
        try await writeSwifterPMPackageInfoCache(
            scratchDirectory: scratchDirectory,
            rootPackagePath: temporaryDirectory,
            dependencyPackagePath: dependencyPackagePath
        )

        given(packageInfoMapper)
            .resolveExternalDependencies(
                path: .any,
                packagePath: .any,
                packageInfos: .any,
                packageToFolder: .any,
                packageToTargetsToArtifactPaths: .any,
                packageModuleAliases: .any,
                packageSettings: .any
            )
            .willReturn([:])

        // When
        _ = try await subject.load(
            packagePath: packagePath,
            packageSettings: .test(),
            disableSandbox: true
        )

        // Then
        verify(manifestLoader)
            .loadPackage(at: .any, disableSandbox: .any)
            .called(0)
        verify(packageInfoMapper)
            .map(
                packageInfo: .value(.alamofire),
                path: .value(dependencyPackagePath),
                packageType: .any,
                packageSettings: .any,
                packageModuleAliases: .any,
                enabledTraits: .any
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func load_when_swifterPMPackageInfoCacheEntryIsStale_fallsBackToManifestLoader() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let scratchDirectory = temporaryDirectory.appending(component: ".build")
        let packagePath = temporaryDirectory.appending(component: "Package.swift")
        let dependencyPackagePath = scratchDirectory.appending(
            components: "registry", "downloads", "Alamofire", "Alamofire", "5.10.2"
        )

        try await writeRegistryWorkspaceState(
            scratchDirectory: scratchDirectory,
            dependencySubpath: "Alamofire/Alamofire/5.10.2"
        )
        try await writeSwiftPackageManifest(at: temporaryDirectory)
        try await writeSwiftPackageManifest(at: dependencyPackagePath)
        let cacheFiles = try await writeSwifterPMPackageInfoCache(
            scratchDirectory: scratchDirectory,
            rootPackagePath: temporaryDirectory,
            dependencyPackagePath: dependencyPackagePath
        )
        try await fileSystem.setFileTimes(
            of: cacheFiles.dependencyPackageInfoPath,
            lastAccessDate: nil,
            lastModificationDate: Date(timeIntervalSince1970: 1)
        )
        try await fileSystem.setFileTimes(
            of: dependencyPackagePath.appending(component: "Package.swift"),
            lastAccessDate: nil,
            lastModificationDate: Date(timeIntervalSince1970: 2)
        )

        given(packageInfoMapper)
            .resolveExternalDependencies(
                path: .any,
                packagePath: .any,
                packageInfos: .any,
                packageToFolder: .any,
                packageToTargetsToArtifactPaths: .any,
                packageModuleAliases: .any,
                packageSettings: .any
            )
            .willReturn([:])

        // When
        _ = try await subject.load(
            packagePath: packagePath,
            packageSettings: .test(),
            disableSandbox: true
        )

        // Then
        verify(manifestLoader)
            .loadPackage(at: .value(temporaryDirectory), disableSandbox: .value(true))
            .called(0)
        verify(manifestLoader)
            .loadPackage(at: .value(dependencyPackagePath), disableSandbox: .value(true))
            .called(1)
    }

    @Test
    func load_when_dependency_via_scm_and_registry() async throws {
        try await withMockedDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
                temporaryDirectory in
                // Given
                let packageSettings = PackageSettings.test()

                let workspacePath = temporaryDirectory.appending(components: [
                    ".build", "workspace-state.json",
                ])
                try await fileSystem.makeDirectory(at: workspacePath.parentDirectory)
                try await fileSystem.writeText(
                    """
                    {
                      "object" : {
                        "artifacts" : [],
                        "dependencies" : [
                          {
                            "basedOn" : null,
                            "packageRef" : {
                              "identity" : "Alamofire.Alamofire",
                              "kind" : "registry",
                              "location" : "Alamofire.Alamofire",
                              "name" : "Alamofire.Alamofire"
                            },
                            "state" : {
                              "name" : "registryDownload",
                              "version" : "5.10.2"
                            },
                            "subpath" : "Alamofire/Alamofire/5.10.2"
                          },
                          {
                            "basedOn" : null,
                            "packageRef" : {
                              "identity" : "Alamofire",
                              "kind" : "remoteSourceControl",
                              "location" : "https://github.com/Alamofire/Alamofire.git",
                              "name" : "Alamofire"
                            },
                            "state" : {
                              "checkoutState" : {
                                "revision" : "540318ecedd63d883069ae7f1ed811a2df00b6ac",
                                "version" : "2.4.0"
                              },
                              "name" : "sourceControlCheckout"
                            },
                            "subpath" : "alamofire"
                          },
                        ],
                      }
                    }
                    """,
                    at: workspacePath
                )

                try await fileSystem.makeDirectory(
                    at: temporaryDirectory.appending(components: [".build", "Derived"])
                )
                try await fileSystem.touch(
                    temporaryDirectory.appending(components: [
                        ".build", "Derived", "Package.resolved",
                    ])
                )
                try await fileSystem.touch(
                    temporaryDirectory.appending(component: "Package.resolved")
                )

                given(packageInfoMapper)
                    .resolveExternalDependencies(
                        path: .any,
                        packagePath: .any,
                        packageInfos: .any,
                        packageToFolder: .any,
                        packageToTargetsToArtifactPaths: .any,
                        packageModuleAliases: .any,
                        packageSettings: .any
                    )
                    .willReturn([:])

                // When
                let (got, _) = try await subject.load(
                    packagePath: temporaryDirectory.appending(component: "Package.swift"),
                    packageSettings: packageSettings,
                    disableSandbox: true
                )

                // Then
                #expect(
                    got.externalProjects.values.map(\.hash) == [
                        "Alamofire.Alamofire-5.10.2",
                    ]
                )

                verify(packageInfoMapper)
                    .map(
                        packageInfo: .any,
                        path: .any,
                        packageType: .matching { packageType in
                            if case .external(
                                origin: .remote,
                                artifactPaths: _,
                                packagePrebuilts: _,
                                derivedXCFrameworksPath: _
                            ) = packageType {
                                return true
                            }
                            return false
                        },
                        packageSettings: .any,
                        packageModuleAliases: .any,
                        enabledTraits: .any
                    )
                    .called(1)
            }
        }
    }

    @Test
    func load_whenWorkspaceStateContainsPrebuilts_sanitizesPathsAndPassesPackagePrebuiltsToMapper() async throws {
        try await withMockedDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
                // Given
                let packageSettings = PackageSettings.test()
                let workspacePath = temporaryDirectory.appending(components: [
                    ".build", "workspace-state.json",
                ])
                let prebuiltPath = temporaryDirectory.appending(components: [
                    ".build", "prebuilts", "swift-syntax",
                ])
                let checkoutPath = temporaryDirectory.appending(components: [
                    ".build", "checkouts", "swift-syntax",
                ])
                let expectedPrebuiltPath = prebuiltPath.pathString.replacingOccurrences(of: "/private/var", with: "/var")
                let expectedCheckoutPath = checkoutPath.pathString.replacingOccurrences(of: "/private/var", with: "/var")

                try await fileSystem.makeDirectory(at: workspacePath.parentDirectory)
                try await fileSystem.writeText(
                    """
                    {
                      "object" : {
                        "artifacts" : [],
                        "dependencies" : [
                          {
                            "basedOn" : null,
                            "packageRef" : {
                              "identity" : "swift-syntax",
                              "kind" : "remoteSourceControl",
                              "location" : "https://github.com/swiftlang/swift-syntax.git",
                              "name" : "swift-syntax"
                            },
                            "state" : {
                              "checkoutState" : {
                                "revision" : "revision",
                                "version" : "601.0.0"
                              },
                              "name" : "sourceControlCheckout"
                            },
                            "subpath" : "swift-syntax"
                          }
                        ],
                        "prebuilts" : [
                          {
                            "identity" : "swift-syntax",
                            "version" : "601.0.0",
                            "libraryName" : "SwiftSyntax",
                            "path" : "\(prebuiltPath.pathString)\\u0000",
                            "checkoutPath" : "\(checkoutPath.pathString)\\u0000",
                            "products" : ["SwiftSyntax"],
                            "includePath" : ["Sources/_SwiftSyntaxCShims/include\\u0000"],
                            "cModules" : ["_SwiftSyntaxCShims"]
                          }
                        ]
                      }
                    }
                    """,
                    at: workspacePath
                )

                try await fileSystem.makeDirectory(
                    at: temporaryDirectory.appending(components: [".build", "Derived"])
                )
                try await fileSystem.touch(
                    temporaryDirectory.appending(components: [
                        ".build", "Derived", "Package.resolved",
                    ])
                )
                try await fileSystem.touch(
                    temporaryDirectory.appending(component: "Package.resolved")
                )

                let swiftPackageManagerController = MockSwiftPackageManagerControlling()
                let manifestLoader = MockManifestLoading()
                given(manifestLoader)
                    .loadPackage(at: .any, disableSandbox: .value(true))
                    .willReturn(.test())
                let contentHasher = MockContentHashing()
                given(contentHasher)
                    .hash(Parameter<[String]>.any)
                    .willProduce { $0.joined(separator: "-") }
                let packageInfoMapper = PackageInfoMapperPrebuiltSpy(
                    packageIdentity: "swift-syntax",
                    productName: "SwiftSyntax"
                )
                let expectedPrebuilt = CapturedPackagePrebuilt(
                    path: expectedPrebuiltPath,
                    checkoutPath: expectedCheckoutPath,
                    includePaths: ["Sources/_SwiftSyntaxCShims/include"]
                )
                let subject = SwiftPackageManagerGraphLoader(
                    swiftPackageManagerController: swiftPackageManagerController,
                    packageInfoMapper: packageInfoMapper,
                    manifestLoader: manifestLoader,
                    fileSystem: fileSystem,
                    contentHasher: contentHasher,
                    cacheDirectoriesProvider: cacheDirectoriesProvider
                )

                // When
                _ = try await subject.load(
                    packagePath: temporaryDirectory.appending(component: "Package.swift"),
                    packageSettings: packageSettings,
                    disableSandbox: true
                )

                // Then
                #expect(packageInfoMapper.mapCallCount == 1)
                #expect(packageInfoMapper.capturedPrebuilt == expectedPrebuilt)
            }
        }
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func load_whenWorkspaceStatePathsAreRelativeToScratchDirectory_resolvesAgainstScratchDir() async throws {
        // Regression: swifterpm now emits paths in workspace-state.json relative to the
        // scratch directory so a cached `.build/` stays portable across hosts. The loader
        // must anchor those relative strings against scratchDirectory when resolving.
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let packageSettings = PackageSettings.test()
        let workspacePath = temporaryDirectory.appending(components: [
            ".build", "workspace-state.json",
        ])
        try await fileSystem.makeDirectory(at: workspacePath.parentDirectory)

        let localPackagePath = temporaryDirectory.appending(component: "LocalDep")
        try await fileSystem.makeDirectory(at: localPackagePath)

        let scratchDirectory = temporaryDirectory.appending(component: ".build")
        let expectedArtifactPath = scratchDirectory.appending(
            try RelativePath(validating: "swifterpm/artifacts/foo/Foo/Foo.xcframework")
        )

        // packageRef.path and state.path are written by swifterpm as
        // `localPackagePath.relative(to: scratchDirectory)` (= "../LocalDep" when
        // scratch is `<temp>/.build`). artifact.path is "swifterpm/artifacts/...".
        try await fileSystem.writeText(
            """
            {
              "object" : {
                "artifacts" : [
                  {
                    "kind" : { "xcframework" : {} },
                    "packageRef" : {
                      "identity" : "foo",
                      "kind" : "remoteSourceControl",
                      "location" : "https://github.com/example/foo.git",
                      "name" : "foo"
                    },
                    "path" : "swifterpm/artifacts/foo/Foo/Foo.xcframework",
                    "source" : {
                      "checksum" : "deadbeef",
                      "type" : "remote",
                      "url" : "https://example.com/Foo.zip"
                    },
                    "targetName" : "Foo"
                  }
                ],
                "dependencies" : [
                  {
                    "basedOn" : null,
                    "packageRef" : {
                      "identity" : "foo",
                      "kind" : "remoteSourceControl",
                      "location" : "https://github.com/example/foo.git",
                      "name" : "foo"
                    },
                    "state" : {
                      "checkoutState" : {
                        "revision" : "abcdef1234567890",
                        "version" : "1.0.0"
                      },
                      "name" : "sourceControlCheckout"
                    },
                    "subpath" : "foo"
                  },
                  {
                    "basedOn" : null,
                    "packageRef" : {
                      "identity" : "local-dep",
                      "kind" : "fileSystem",
                      "path" : "../LocalDep",
                      "name" : "LocalDep"
                    },
                    "state" : {
                      "name" : "fileSystem",
                      "path" : "../LocalDep"
                    },
                    "subpath" : "local-dep"
                  }
                ]
              }
            }
            """,
            at: workspacePath
        )

        try await fileSystem.makeDirectory(
            at: temporaryDirectory.appending(components: [".build", "Derived"])
        )
        try await fileSystem.touch(
            temporaryDirectory.appending(components: [".build", "Derived", "Package.resolved"])
        )
        try await fileSystem.touch(
            temporaryDirectory.appending(component: "Package.resolved")
        )

        given(packageInfoMapper)
            .resolveExternalDependencies(
                path: .any,
                packagePath: .any,
                packageInfos: .any,
                packageToFolder: .any,
                packageToTargetsToArtifactPaths: .any,
                packageModuleAliases: .any,
                packageSettings: .any
            )
            .willReturn([:])

        // When
        _ = try await subject.load(
            packagePath: temporaryDirectory.appending(component: "Package.swift"),
            packageSettings: packageSettings,
            disableSandbox: true
        )

        // Then: artifact paths arrive at the mapper resolved against scratchDirectory.
        let expectedDerivedXCFrameworksPath = temporaryDirectory.appending(
            components: ".build",
            Constants.DerivedDirectory.dependenciesDerivedDirectory,
            Constants.DerivedDirectory.dependenciesXCFrameworkDirectory
        )
        verify(packageInfoMapper)
            .map(
                packageInfo: .any,
                path: .any,
                packageType: .matching { packageType in
                    guard case let .external(
                        origin: _,
                        artifactPaths: artifactPaths,
                        packagePrebuilts: _,
                        derivedXCFrameworksPath: derivedXCFrameworksPath
                    ) = packageType
                    else { return false }
                    return artifactPaths["Foo"] == expectedArtifactPath
                        && derivedXCFrameworksPath == expectedDerivedXCFrameworksPath
                },
                packageSettings: .any,
                packageModuleAliases: .any,
                enabledTraits: .any
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func load_when_dependency_via_local_registry_and_scm() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // Given
        let packageSettings = PackageSettings.test()

        let workspacePath = temporaryDirectory.appending(components: [
            ".build", "workspace-state.json",
        ])
        try await fileSystem.makeDirectory(at: workspacePath.parentDirectory)

        let localPackagePath = temporaryDirectory.appending(component: "Alamofire")
        try await fileSystem.makeDirectory(at: localPackagePath)

        try await fileSystem.writeText(
            """
            {
              "object" : {
                "artifacts" : [],
                "dependencies" : [
                  {
                    "basedOn" : null,
                    "packageRef" : {
                      "identity" : "Alamofire.Alamofire",
                      "kind" : "registry",
                      "location" : "Alamofire.Alamofire",
                      "name" : "Alamofire.Alamofire"
                    },
                    "state" : {
                      "name" : "registryDownload",
                      "version" : "5.10.2"
                    },
                    "subpath" : "Alamofire/Alamofire/5.10.2"
                  },
                  {
                    "basedOn" : null,
                    "packageRef" : {
                      "identity" : "Alamofire",
                      "kind" : "remoteSourceControl",
                      "location" : "https://github.com/Alamofire/Alamofire.git",
                      "name" : "Alamofire"
                    },
                    "state" : {
                      "checkoutState" : {
                        "revision" : "540318ecedd63d883069ae7f1ed811a2df00b6ac",
                        "version" : "2.4.0"
                      },
                      "name" : "sourceControlCheckout"
                    },
                    "subpath" : "alamofire"
                  },
                  {
                    "basedOn" : null,
                    "packageRef" : {
                      "identity" : "Alamofire",
                      "kind" : "fileSystem",
                      "path" : "\(localPackagePath.pathString)",
                      "name" : "Alamofire"
                    },
                    "state" : {
                      "name" : "fileSystem",
                      "path" : "\(localPackagePath.pathString)"
                    },
                    "subpath" : "Alamofire"
                  },
                ],
              }
            }
            """,
            at: workspacePath
        )

        try await fileSystem.makeDirectory(
            at: temporaryDirectory.appending(components: [".build", "Derived"])
        )
        try await fileSystem.touch(
            temporaryDirectory.appending(components: [
                ".build", "Derived", "Package.resolved",
            ])
        )
        try await fileSystem.touch(
            temporaryDirectory.appending(component: "Package.resolved")
        )

        given(packageInfoMapper)
            .resolveExternalDependencies(
                path: .any,
                packagePath: .any,
                packageInfos: .any,
                packageToFolder: .any,
                packageToTargetsToArtifactPaths: .any,
                packageModuleAliases: .any,
                packageSettings: .any
            )
            .willReturn([:])

        // When
        let (got, _) = try await subject.load(
            packagePath: temporaryDirectory.appending(component: "Package.swift"),
            packageSettings: packageSettings,
            disableSandbox: true
        )

        // Then
        #expect(
            got.externalProjects.values.map(\.hash) == [nil]
        )

        verify(packageInfoMapper)
            .map(
                packageInfo: .any,
                path: .any,
                packageType: .matching { packageType in
                    if case .external(
                        origin: .local,
                        artifactPaths: _,
                        packagePrebuilts: _,
                        derivedXCFrameworksPath: _
                    ) = packageType {
                        return true
                    }
                    return false
                },
                packageSettings: .any,
                packageModuleAliases: .any,
                enabledTraits: .any
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func load_when_dependency_via_local_and_registry_case_insensitive() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // Given
        let packageSettings = PackageSettings.test()

        let workspacePath = temporaryDirectory.appending(components: [
            ".build", "workspace-state.json",
        ])
        try await fileSystem.makeDirectory(at: workspacePath.parentDirectory)

        let localPackagePath = temporaryDirectory.appending(component: "Alamofire")
        try await fileSystem.makeDirectory(at: localPackagePath)

        try await fileSystem.writeText(
            """
            {
              "object" : {
                "artifacts" : [],
                "dependencies" : [
                  {
                    "basedOn" : null,
                    "packageRef" : {
                      "identity" : "alamofire.alamofire",
                      "kind" : "registry",
                      "location" : "alamofire.alamofire",
                      "name" : "alamofire.alamofire"
                    },
                    "state" : {
                      "name" : "registryDownload",
                      "version" : "5.10.2"
                    },
                    "subpath" : "alamofire/alamofire/5.10.2"
                  },
                  {
                    "basedOn" : null,
                    "packageRef" : {
                      "identity" : "Alamofire",
                      "kind" : "fileSystem",
                      "path" : "\(localPackagePath.pathString)",
                      "name" : "Alamofire"
                    },
                    "state" : {
                      "name" : "fileSystem",
                      "path" : "\(localPackagePath.pathString)"
                    },
                    "subpath" : "Alamofire"
                  },
                ],
              }
            }
            """,
            at: workspacePath
        )

        try await fileSystem.makeDirectory(
            at: temporaryDirectory.appending(components: [".build", "Derived"])
        )
        try await fileSystem.touch(
            temporaryDirectory.appending(components: [
                ".build", "Derived", "Package.resolved",
            ])
        )
        try await fileSystem.touch(
            temporaryDirectory.appending(component: "Package.resolved")
        )

        given(packageInfoMapper)
            .resolveExternalDependencies(
                path: .any,
                packagePath: .any,
                packageInfos: .any,
                packageToFolder: .any,
                packageToTargetsToArtifactPaths: .any,
                packageModuleAliases: .any,
                packageSettings: .any
            )
            .willReturn([:])

        // When
        let (got, _) = try await subject.load(
            packagePath: temporaryDirectory.appending(component: "Package.swift"),
            packageSettings: packageSettings,
            disableSandbox: true
        )

        // Then
        #expect(
            got.externalProjects.values.map(\.hash) == [nil]
        )
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies(), .withMockedSwiftVersionProvider)
    func load_reusesTheCachedGraph_whenInputsAreUnchanged() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let scratchDirectory = temporaryDirectory.appending(component: ".build")
        let packagePath = temporaryDirectory.appending(component: "Package.swift")
        let dependencyPackagePath = scratchDirectory.appending(
            components: "registry", "downloads", "Alamofire", "Alamofire", "5.10.2"
        )

        // Given
        given(try #require(SwiftVersionProvider.mocked)).swiftVersion().willReturn("6.1.0")
        try await writeRegistryWorkspaceState(
            scratchDirectory: scratchDirectory,
            dependencySubpath: "Alamofire/Alamofire/5.10.2"
        )
        try await writeSwiftPackageManifest(at: temporaryDirectory)
        try await writeSwiftPackageManifest(at: dependencyPackagePath)

        let packageInfoMapper = PackageInfoMapperPrebuiltSpy(packageIdentity: "unused", productName: "unused")
        let subject = cachingSubject(
            packageInfoMapper: packageInfoMapper,
            cacheDirectory: temporaryDirectory.appending(component: "GraphCache")
        )

        // When
        let (firstGraph, _) = try await subject.load(
            packagePath: packagePath,
            packageSettings: .test(),
            disableSandbox: true
        )
        let (secondGraph, _) = try await subject.load(
            packagePath: packagePath,
            packageSettings: .test(),
            disableSandbox: true
        )

        // Then
        #expect(packageInfoMapper.mapCallCount == 1)
        #expect(secondGraph == firstGraph)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies(), .withMockedSwiftVersionProvider)
    func load_mapsAgain_whenTheWorkspaceStateChanges() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let scratchDirectory = temporaryDirectory.appending(component: ".build")
        let packagePath = temporaryDirectory.appending(component: "Package.swift")
        let dependencyPackagePath = scratchDirectory.appending(
            components: "registry", "downloads", "Alamofire", "Alamofire", "5.10.2"
        )

        // Given
        given(try #require(SwiftVersionProvider.mocked)).swiftVersion().willReturn("6.1.0")
        try await writeRegistryWorkspaceState(
            scratchDirectory: scratchDirectory,
            dependencySubpath: "Alamofire/Alamofire/5.10.2"
        )
        try await writeSwiftPackageManifest(at: temporaryDirectory)
        try await writeSwiftPackageManifest(at: dependencyPackagePath)

        let packageInfoMapper = PackageInfoMapperPrebuiltSpy(packageIdentity: "unused", productName: "unused")
        let subject = cachingSubject(
            packageInfoMapper: packageInfoMapper,
            cacheDirectory: temporaryDirectory.appending(component: "GraphCache")
        )

        // When
        _ = try await subject.load(packagePath: packagePath, packageSettings: .test(), disableSandbox: true)
        try await writeRegistryWorkspaceState(
            scratchDirectory: scratchDirectory,
            dependencySubpath: "Alamofire/Alamofire/5.10.2",
            version: "5.10.3"
        )
        _ = try await subject.load(packagePath: packagePath, packageSettings: .test(), disableSandbox: true)

        // Then
        #expect(packageInfoMapper.mapCallCount == 2)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies(), .withMockedSwiftVersionProvider)
    func load_mapsAgain_whenThePackageSettingsChange() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let scratchDirectory = temporaryDirectory.appending(component: ".build")
        let packagePath = temporaryDirectory.appending(component: "Package.swift")
        let dependencyPackagePath = scratchDirectory.appending(
            components: "registry", "downloads", "Alamofire", "Alamofire", "5.10.2"
        )

        // Given
        given(try #require(SwiftVersionProvider.mocked)).swiftVersion().willReturn("6.1.0")
        try await writeRegistryWorkspaceState(
            scratchDirectory: scratchDirectory,
            dependencySubpath: "Alamofire/Alamofire/5.10.2"
        )
        try await writeSwiftPackageManifest(at: temporaryDirectory)
        try await writeSwiftPackageManifest(at: dependencyPackagePath)

        let packageInfoMapper = PackageInfoMapperPrebuiltSpy(packageIdentity: "unused", productName: "unused")
        let subject = cachingSubject(
            packageInfoMapper: packageInfoMapper,
            cacheDirectory: temporaryDirectory.appending(component: "GraphCache")
        )

        // When
        _ = try await subject.load(packagePath: packagePath, packageSettings: .test(), disableSandbox: true)
        _ = try await subject.load(
            packagePath: packagePath,
            packageSettings: .test(productTypes: ["Alamofire": .framework]),
            disableSandbox: true
        )

        // Then
        #expect(packageInfoMapper.mapCallCount == 2)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies(), .withMockedSwiftVersionProvider)
    func load_mapsAgain_whenALocalPackageChanges() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let scratchDirectory = temporaryDirectory.appending(component: ".build")
        let packagePath = temporaryDirectory.appending(component: "Package.swift")
        let localPackagePath = temporaryDirectory.appending(component: "LocalDep")

        // Given
        given(try #require(SwiftVersionProvider.mocked)).swiftVersion().willReturn("6.1.0")
        try await writeLocalDependencyWorkspaceState(
            scratchDirectory: scratchDirectory,
            localPackagePath: localPackagePath
        )
        try await writeSwiftPackageManifest(at: temporaryDirectory)
        try await writeSwiftPackageManifest(at: localPackagePath)

        let packageInfoMapper = PackageInfoMapperPrebuiltSpy(packageIdentity: "unused", productName: "unused")
        let subject = cachingSubject(
            packageInfoMapper: packageInfoMapper,
            cacheDirectory: temporaryDirectory.appending(component: "GraphCache")
        )

        // When: an unchanged local package hits the cache, a content change invalidates it.
        _ = try await subject.load(packagePath: packagePath, packageSettings: .test(), disableSandbox: true)
        _ = try await subject.load(packagePath: packagePath, packageSettings: .test(), disableSandbox: true)
        #expect(packageInfoMapper.mapCallCount == 1)

        try await fileSystem.makeDirectory(at: localPackagePath.appending(component: "Sources"))
        try await fileSystem.writeText(
            "public let localDep = 1",
            at: localPackagePath.appending(components: "Sources", "LocalDep.swift")
        )
        _ = try await subject.load(packagePath: packagePath, packageSettings: .test(), disableSandbox: true)

        // Then
        #expect(packageInfoMapper.mapCallCount == 2)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies(), .withMockedSwiftVersionProvider)
    func load_mapsAgain_whenDerivedFilesAreRemoved() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let scratchDirectory = temporaryDirectory.appending(component: ".build")
        let packagePath = temporaryDirectory.appending(component: "Package.swift")
        let dependencyPackagePath = scratchDirectory.appending(
            components: "registry", "downloads", "Alamofire", "Alamofire", "5.10.2"
        )

        // Given: a module map that mapping would have written as a side effect.
        given(try #require(SwiftVersionProvider.mocked)).swiftVersion().willReturn("6.1.0")
        try await writeRegistryWorkspaceState(
            scratchDirectory: scratchDirectory,
            dependencySubpath: "Alamofire/Alamofire/5.10.2"
        )
        try await writeSwiftPackageManifest(at: temporaryDirectory)
        try await writeSwiftPackageManifest(at: dependencyPackagePath)
        let derivedModuleMapPath = scratchDirectory.appending(
            components: Constants.DerivedDirectory.dependenciesDerivedDirectory,
            Constants.DerivedDirectory.dependenciesModuleMapsDirectory,
            "Alamofire",
            "Alamofire.modulemap"
        )
        try await fileSystem.makeDirectory(at: derivedModuleMapPath.parentDirectory)
        try await fileSystem.writeText("module Alamofire {}", at: derivedModuleMapPath)

        let packageInfoMapper = PackageInfoMapperPrebuiltSpy(packageIdentity: "unused", productName: "unused")
        let subject = cachingSubject(
            packageInfoMapper: packageInfoMapper,
            cacheDirectory: temporaryDirectory.appending(component: "GraphCache")
        )

        // When: removing a recorded derived file invalidates the entry, so mapping recreates it.
        _ = try await subject.load(packagePath: packagePath, packageSettings: .test(), disableSandbox: true)
        _ = try await subject.load(packagePath: packagePath, packageSettings: .test(), disableSandbox: true)
        #expect(packageInfoMapper.mapCallCount == 1)

        try await fileSystem.remove(derivedModuleMapPath)
        _ = try await subject.load(packagePath: packagePath, packageSettings: .test(), disableSandbox: true)

        // Then
        #expect(packageInfoMapper.mapCallCount == 2)
    }

    private func cachingSubject(
        packageInfoMapper: PackageInfoMapping,
        cacheDirectory: Path.AbsolutePath
    ) -> SwiftPackageManagerGraphLoader {
        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .any)
            .willReturn(cacheDirectory)
        return SwiftPackageManagerGraphLoader(
            swiftPackageManagerController: swiftPackageManagerController,
            packageInfoMapper: packageInfoMapper,
            manifestLoader: manifestLoader,
            fileSystem: fileSystem,
            contentHasher: contentHasher,
            cacheDirectoriesProvider: cacheDirectoriesProvider
        )
    }

    private func writeRegistryWorkspaceState(
        scratchDirectory: Path.AbsolutePath,
        dependencySubpath: String,
        version: String = "5.10.2"
    ) async throws {
        let workspacePath = scratchDirectory.appending(component: "workspace-state.json")
        try await fileSystem.makeDirectory(at: workspacePath.parentDirectory)
        try await fileSystem.writeText(
            """
            {
              "object" : {
                "artifacts" : [],
                "dependencies" : [
                  {
                    "basedOn" : null,
                    "packageRef" : {
                      "identity" : "Alamofire.Alamofire",
                      "kind" : "registry",
                      "location" : "Alamofire.Alamofire",
                      "name" : "Alamofire.Alamofire"
                    },
                    "state" : {
                      "name" : "registryDownload",
                      "version" : "\(version)"
                    },
                    "subpath" : "\(dependencySubpath)"
                  }
                ]
              }
            }
            """,
            at: workspacePath
        )
    }

    private func writeLocalDependencyWorkspaceState(
        scratchDirectory: Path.AbsolutePath,
        localPackagePath: Path.AbsolutePath
    ) async throws {
        let workspacePath = scratchDirectory.appending(component: "workspace-state.json")
        try await fileSystem.makeDirectory(at: workspacePath.parentDirectory)
        try await fileSystem.writeText(
            """
            {
              "object" : {
                "artifacts" : [],
                "dependencies" : [
                  {
                    "basedOn" : null,
                    "packageRef" : {
                      "identity" : "local-dep",
                      "kind" : "fileSystem",
                      "path" : "\(localPackagePath.pathString)",
                      "name" : "LocalDep"
                    },
                    "state" : {
                      "name" : "fileSystem",
                      "path" : "\(localPackagePath.pathString)"
                    },
                    "subpath" : "local-dep"
                  }
                ]
              }
            }
            """,
            at: workspacePath
        )
    }

    private func writeSwiftPackageManifest(at packagePath: Path.AbsolutePath) async throws {
        if try await !fileSystem.exists(packagePath, isDirectory: true) {
            try await fileSystem.makeDirectory(at: packagePath)
        }
        try await fileSystem.writeText(
            """
            // swift-tools-version: 5.9
            import PackageDescription

            let package = Package(name: "\(packagePath.basename)")
            """,
            at: packagePath.appending(component: "Package.swift")
        )
    }

    private struct SwifterPMPackageInfoCacheFiles {
        let dependencyPackageInfoPath: Path.AbsolutePath
    }

    @discardableResult
    private func writeSwifterPMPackageInfoCache(
        scratchDirectory: Path.AbsolutePath,
        rootPackagePath: Path.AbsolutePath,
        dependencyPackagePath: Path.AbsolutePath
    ) async throws -> SwifterPMPackageInfoCacheFiles {
        let cacheDirectory = scratchDirectory.appending(components: "swifterpm", "package-info")
        let packagesCacheDirectory = cacheDirectory.appending(component: "packages")
        let rootPackageInfoPath = cacheDirectory.appending(component: "root.json")
        let dependencyPackageInfoPath = packagesCacheDirectory.appending(component: "Alamofire.Alamofire-5.10.2.json")

        try await fileSystem.makeDirectory(at: scratchDirectory.appending(component: "swifterpm"))
        try await fileSystem.makeDirectory(at: cacheDirectory)
        try await fileSystem.makeDirectory(at: packagesCacheDirectory)
        try await fileSystem.writeText(PackageInfo.testJSON, at: rootPackageInfoPath)
        try await fileSystem.writeText(PackageInfo.alamofireJSON, at: dependencyPackageInfoPath)
        try await fileSystem.writeText(
            """
            {
              "schema_version" : 1,
              "generated_at_unix" : 1,
              "root" : {
                "identity" : "root",
                "kind" : "root",
                "location" : "\(rootPackagePath.pathString)",
                "revision" : null,
                "version" : null,
                "package_path" : "\(rootPackagePath.pathString)",
                "package_info_path" : "\(rootPackageInfoPath.pathString)"
              },
              "packages" : [
                {
                  "identity" : "Alamofire.Alamofire",
                  "kind" : "registry",
                  "location" : "Alamofire.Alamofire",
                  "revision" : null,
                  "version" : "5.10.2",
                  "package_path" : "\(dependencyPackagePath.pathString)",
                  "package_info_path" : "\(dependencyPackageInfoPath.pathString)"
                }
              ]
            }
            """,
            at: cacheDirectory.appending(component: "index.json")
        )

        return SwifterPMPackageInfoCacheFiles(dependencyPackageInfoPath: dependencyPackageInfoPath)
    }
}
