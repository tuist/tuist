import FileSystem
import Foundation
import Testing
import XcodeGraph
@testable import XcodeGraphMapper

struct PackageMapperTests: Sendable {
    private let fileSystem = FileSystem()

    @Test
    func map_package() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "PackageMapperTests") { path in
            // Given
            let subject = PackageMapper()
            let sourcesLibraryAPath = path.appending(components: "Sources", "LibraryA")
            try await fileSystem.makeDirectory(at: sourcesLibraryAPath)
            try await fileSystem.touch(sourcesLibraryAPath.appending(component: "File.swift"))
            let testsLibraryAPath = path.appending(components: "Tests", "LibraryATests")
            try await fileSystem.makeDirectory(at: testsLibraryAPath)
            try await fileSystem.touch(testsLibraryAPath.appending(component: "TestFile.swift"))

            // When
            let got = try await subject.map(
                .test(
                    name: "LibraryA",
                    targets: [
                        .test(
                            name: "LibraryA",
                            dependencies: [
                                .product(
                                    name: "Alamofire",
                                    package: "Alamofire",
                                    moduleAliases: nil,
                                    condition: nil
                                ),
                                .byName(
                                    name: "LibraryB",
                                    condition: nil
                                ),
                                .product(
                                    name: "LibraryCProduct",
                                    package: "LibraryC",
                                    moduleAliases: nil,
                                    condition: PackageInfo.PackageConditionDescription(platformNames: ["ios"], config: nil)
                                ),
                                .byName(
                                    name: "LibraryAHelpers",
                                    condition: nil
                                ),
                            ]
                        ),
                        .test(
                            name: "LibraryATests",
                            dependencies: [
                                .byName(
                                    name: "LibraryA",
                                    condition: nil
                                ),
                            ],
                            type: .test
                        ),
                        .test(
                            name: "LibraryAHelpers"
                        ),
                    ]
                ),
                packages: [
                    "LibraryB": path.appending(component: "LibraryB"),
                    "LibraryC": path.appending(component: "LibraryC"),
                ],
                at: path
            )

            // Then
            #expect(
                got == Project(
                    path: path,
                    sourceRootPath: path,
                    xcodeProjPath: path,
                    name: "LibraryA",
                    organizationName: nil,
                    classPrefix: nil,
                    defaultKnownRegions: nil,
                    developmentRegion: nil,
                    options: Project.Options(
                        automaticSchemesOptions: .disabled,
                        disableBundleAccessors: true,
                        disableShowEnvironmentVarsInScriptPhases: true,
                        disableSynthesizedResourceAccessors: true,
                        textSettings: Project.Options.TextSettings(
                            usesTabs: nil,
                            indentWidth: nil,
                            tabWidth: nil,
                            wrapsLines: nil
                        )
                    ),
                    settings: Settings(configurations: [:]),
                    filesGroup: .group(name: "LibraryA"),
                    targets: [
                        Target(
                            name: "LibraryA",
                            destinations: Destinations(Destination.allCases),
                            product: .staticFramework,
                            productName: nil,
                            bundleId: "",
                            sources: [
                                SourceFile(path: sourcesLibraryAPath.appending(component: "File.swift")),
                            ],
                            filesGroup: .group(name: "LibraryA"),
                            dependencies: [
                                .package(
                                    product: "Alamofire",
                                    type: .runtime,
                                    condition: nil
                                ),
                                .project(
                                    target: "LibraryB",
                                    path: path.appending(component: "LibraryB"),
                                    status: .required,
                                    condition: nil
                                ),
                                .project(
                                    target: "LibraryCProduct",
                                    path: path.appending(component: "LibraryC"),
                                    status: .required,
                                    condition: .when([.ios])
                                ),
                                .target(
                                    name: "LibraryAHelpers",
                                    status: .required,
                                    condition: nil
                                ),
                            ]
                        ),
                        Target(
                            name: "LibraryATests",
                            destinations: Destinations(Destination.allCases),
                            product: .unitTests,
                            productName: nil,
                            bundleId: "",
                            sources: [
                                SourceFile(path: path.appending(components: "Tests", "LibraryATests", "TestFile.swift")),
                            ],
                            filesGroup: .group(name: "LibraryATests"),
                            dependencies: [
                                .target(
                                    name: "LibraryA",
                                    status: .required,
                                    condition: nil
                                ),
                            ]
                        ),
                        Target(
                            name: "LibraryAHelpers",
                            destinations: Destinations(Destination.allCases),
                            product: .staticFramework,
                            productName: nil,
                            bundleId: "",
                            sources: [],
                            filesGroup: .group(name: "LibraryAHelpers"),
                            dependencies: []
                        ),
                    ],
                    packages: [],
                    schemes: [],
                    ideTemplateMacros: nil,
                    additionalFiles: [],
                    resourceSynthesizers: [],
                    lastUpgradeCheck: nil,
                    type: .local
                )
            )
        }
    }
}
