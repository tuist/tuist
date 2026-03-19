import FileSystem
import Foundation
import Mockable
import Testing
import TuistCore
import TuistNooraTesting
import TuistSupport
import TuistTesting
@testable import TuistLoader

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
                        packageInfos: .any,
                        packageToFolder: .any,
                        packageToTargetsToArtifactPaths: .any,
                        packageModuleAliases: .any
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
                        packageInfos: .any,
                        packageToFolder: .any,
                        packageToTargetsToArtifactPaths: .any,
                        packageModuleAliases: .any
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
            }
        }
    }

    @Test
    func load_when_packagesShareManifestName_preservesDistinctPackageReferenceNames() async throws {
        try await withMockedDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
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
                              "identity" : "apple.swift-async-algorithms",
                              "kind" : "registry",
                              "location" : "apple.swift-async-algorithms",
                              "name" : "apple.swift-async-algorithms"
                            },
                            "state" : {
                              "name" : "registryDownload",
                              "version" : "1.1.3"
                            },
                            "subpath" : "apple/swift-async-algorithms/1.1.3"
                          },
                          {
                            "basedOn" : null,
                            "packageRef" : {
                              "identity" : "coenttb.swift-async-algorithms-fork",
                              "kind" : "registry",
                              "location" : "coenttb.swift-async-algorithms-fork",
                              "name" : "coenttb.swift-async-algorithms-fork"
                            },
                            "state" : {
                              "name" : "registryDownload",
                              "version" : "1.2.0"
                            },
                            "subpath" : "coenttb/swift-async-algorithms-fork/1.2.0"
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

                given(manifestLoader)
                    .loadPackage(at: .any, disableSandbox: .value(true))
                    .willProduce { path, _ in
                        if path == temporaryDirectory {
                            return .test(name: "Root")
                        } else {
                            return .test(name: "swift-async-algorithms")
                        }
                    }

                given(packageInfoMapper)
                    .resolveExternalDependencies(
                        path: .any,
                        packageInfos: .any,
                        packageToFolder: .any,
                        packageToTargetsToArtifactPaths: .any,
                        packageModuleAliases: .any
                    )
                    .willProduce { _, packageInfos, _, _, _ in
                        #expect(Set(packageInfos.keys) == [
                            "apple.swift-async-algorithms",
                            "coenttb.swift-async-algorithms-fork",
                        ])
                        #expect(Set(packageInfos.values.map(\.name)) == [
                            "apple.swift-async-algorithms",
                            "coenttb.swift-async-algorithms-fork",
                        ])
                        return [:]
                    }

                _ = try await subject.load(
                    packagePath: temporaryDirectory.appending(component: "Package.swift"),
                    packageSettings: packageSettings,
                    disableSandbox: true
                )
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
                packageInfos: .any,
                packageToFolder: .any,
                packageToTargetsToArtifactPaths: .any,
                packageModuleAliases: .any
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
                packageInfos: .any,
                packageToFolder: .any,
                packageToTargetsToArtifactPaths: .any,
                packageModuleAliases: .any
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

    @Test
    func load_warnOutdatedDependencies() async throws {
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
                        "dependencies" : []
                      }
                    }
                    """,
                    at: workspacePath
                )

                try await fileSystem.makeDirectory(
                    at: temporaryDirectory.appending(components: [".build", "Derived"])
                )
                let savedPackageResolvedPath = temporaryDirectory.appending(components: [
                    ".build", "Derived", "Package.resolved",
                ])
                let currentPackageResolvedPath = temporaryDirectory.appending(
                    component: "Package.resolved"
                )
                try await fileSystem.writeText("outdated", at: savedPackageResolvedPath)
                try await fileSystem.touch(currentPackageResolvedPath)

                given(packageInfoMapper)
                    .resolveExternalDependencies(
                        path: .any,
                        packageInfos: .any,
                        packageToFolder: .any,
                        packageToTargetsToArtifactPaths: .any,
                        packageModuleAliases: .any
                    )
                    .willReturn([:])

                // When
                let (_, lintingIssues) = try await subject.load(
                    packagePath: temporaryDirectory.appending(component: "Package.swift"),
                    packageSettings: packageSettings,
                    disableSandbox: true
                )

                // Then
                #expect(
                    lintingIssues.contains { $0.reason.contains("We detected outdated dependencies") }
                )
            }
        }
    }
}
