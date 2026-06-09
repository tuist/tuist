import FileSystem
import Foundation
import Mockable
import Path
import Synchronization
import Testing
import TSCBasic
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

struct SwiftPackageManagerGraphLoaderTests {
    private let swiftPackageManagerController = MockSwiftPackageManagerControlling()
    private let packageInfoMapper = MockPackageInfoMapping()
    private let manifestLoader = MockManifestLoading()
    private let fileSystem = FileSystem()
    private let contentHasher = MockContentHashing()
    private let subject: SwiftPackageManagerGraphLoader

    init() {
        subject = SwiftPackageManagerGraphLoader(
            swiftPackageManagerController: swiftPackageManagerController,
            packageInfoMapper: packageInfoMapper,
            manifestLoader: manifestLoader,
            fileSystem: fileSystem,
            contentHasher: contentHasher
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
            contentHasher: contentHasher
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
                            if case .external(origin: .remote, artifactPaths: _, packagePrebuilts: _) = packageType {
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
    func load_whenWorkspaceStateContainsPrebuilts_passesPackagePrebuiltsToMapper() async throws {
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
                            "path" : "\(prebuiltPath.pathString)",
                            "checkoutPath" : "\(checkoutPath.pathString)",
                            "products" : ["SwiftSyntax"],
                            "includePath" : ["Sources/_SwiftSyntaxCShims/include"],
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

                // Then
                verify(packageInfoMapper)
                    .map(
                        packageInfo: .any,
                        path: .any,
                        packageType: .matching { packageType in
                            guard case let .external(
                                origin: .remote,
                                artifactPaths: _,
                                packagePrebuilts: packagePrebuilts
                            ) = packageType,
                                let prebuilt = packagePrebuilts["swift-syntax"]?["SwiftSyntax"]
                            else {
                                return false
                            }

                            return prebuilt.path == prebuiltPath
                                && prebuilt.checkoutPath == checkoutPath
                                && prebuilt.includePath?.map(\.pathString) == ["Sources/_SwiftSyntaxCShims/include"]
                        },
                        packageSettings: .any,
                        packageModuleAliases: .any,
                        enabledTraits: .any
                    )
                    .called(1)
            }
        }
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
                    if case .external(origin: .local, artifactPaths: _, packagePrebuilts: _) = packageType {
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

    private func writeRegistryWorkspaceState(
        scratchDirectory: Path.AbsolutePath,
        dependencySubpath: String
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
                      "version" : "5.10.2"
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
