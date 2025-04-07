import FileSystem
import Foundation
import Mockable
import ServiceContextModule
import Testing
import TuistCore
import TuistSupport
import TuistSupportTesting

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
            .loadPackage(at: .any)
            .willReturn(.test())
        given(packageInfoMapper)
            .map(
                packageInfo: .any,
                path: .any,
                packageType: .any,
                packageSettings: .any,
                packageModuleAliases: .any
            )
            .willReturn(.test())
    }

    @Test
    func test_load() async throws {
        try await ServiceContext.withTestingDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
                // Given
                let packageSettings = PackageSettings.test()

                let workspacePath = temporaryDirectory.appending(components: [".build", "workspace-state.json"])
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

                try await fileSystem.makeDirectory(at: temporaryDirectory.appending(components: [".build", "Derived"]))
                try await fileSystem.touch(temporaryDirectory.appending(components: [".build", "Derived", "Package.resolved"]))
                try await fileSystem.touch(temporaryDirectory.appending(component: "Package.resolved"))

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
                let got = try await subject.load(
                    packagePath: temporaryDirectory.appending(component: "Package.swift"),
                    packageSettings: packageSettings
                )

                // Then
                #expect(
                    got.externalProjects.values.map(\.hash) == [
                        "Alamofire.Alamofire-5.10.2",
                    ]
                )
                #expect(
                    ServiceContext.current?.recordedUI()
                        .contains("We detected outdated dependencies.") == false
                )
            }
        }
    }

    @Test
    func test_load_warnOutdatedDependencies() async throws {
        try await ServiceContext.withTestingDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
                // Given
                let packageSettings = PackageSettings.test()

                let workspacePath = temporaryDirectory.appending(components: [".build", "workspace-state.json"])
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

                try await fileSystem.makeDirectory(at: temporaryDirectory.appending(components: [".build", "Derived"]))
                let savedPackageResolvedPath = temporaryDirectory.appending(components: [".build", "Derived", "Package.resolved"])
                let currentPackageResolvedPath = temporaryDirectory.appending(component: "Package.resolved")
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
                _ = try await subject.load(
                    packagePath: temporaryDirectory.appending(component: "Package.swift"),
                    packageSettings: packageSettings
                )

                // Then
                #expect(
                    ServiceContext.current?.recordedUI()
                        .contains("We detected outdated dependencies") == true
                )
            }
        }
    }
}
