import FileSystem
import Foundation
import Mockable
import Synchronization
import Testing
import TSCBasic
import TuistCore
import TuistNooraTesting
import TuistSupport
import TuistTesting
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
                            if case .external(origin: .remote, artifactPaths: _) = packageType {
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
                    if case .external(origin: .local, artifactPaths: _) = packageType {
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
}
