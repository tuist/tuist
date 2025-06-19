import Foundation
import Mockable
import Path
import TuistCore
import TuistLoader
import TuistSupport
import TuistTesting
import XcodeGraph
import XCTest
@testable import TuistKit

final class StaticXCFrameworkModuleMapGraphMapperTests: TuistUnitTestCase {
    private var subject: StaticXCFrameworkModuleMapGraphMapper!
    private var manifestFilesLocator: MockManifestFilesLocating!

    override func setUp() {
        super.setUp()

        manifestFilesLocator = MockManifestFilesLocating()
        subject = StaticXCFrameworkModuleMapGraphMapper(
            manifestFilesLocator: manifestFilesLocator
        )
    }

    override func tearDown() {
        manifestFilesLocator = nil
        subject = nil

        super.tearDown()
    }

    func test_map_when_static_xcframework_library_linked_via_dynamic_xcframework() async throws {
        // Given
        let projectPath = try temporaryPath()
            .appending(component: "Project")
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(
                projectPath.appending(components: Constants.tuistDirectoryName, Constants.SwiftPackageManager.packageSwiftName)
            )
        let googleMapsPath = projectPath
            .parentDirectory
            .appending(component: "GoogleMaps.xcframework")
        let googleMapsHeadersPath = googleMapsPath.appending(components: "ios-arm64", "Headers")
        try await fileSystem.makeDirectory(at: googleMapsHeadersPath)
        try await fileSystem.writeText(
            "modulemap",
            at: googleMapsHeadersPath.appending(component: "module.modulemap")
        )
        try await fileSystem.writeText(
            """
            #import <GoogleMaps/GMSIndoorBuilding.h>
            #import <GoogleMaps/GMSIndoorLevel.h>
            """,
            at: googleMapsHeadersPath.appending(component: "GoogleMaps.h")
        )

        let derivedDirectory = projectPath.appending(
            components: [
                Constants.tuistDirectoryName,
                Constants.SwiftPackageManager.packageBuildDirectoryName,
                Constants.DerivedDirectory.dependenciesDerivedDirectory,
            ]
        )

        let graph: Graph = .test(
            name: "App",
            path: projectPath,
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(
                            name: "App"
                        ),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "App", path: projectPath): [
                    .testXCFramework(
                        path: try temporaryPath()
                            .appending(component: "DynamicFramework.xcframework")
                    ),
                ],
                .testXCFramework(
                    path: try temporaryPath()
                        .appending(component: "DynamicFramework.xcframework")
                ): [
                    .testXCFramework(
                        path: googleMapsPath,
                        infoPlist: .test(
                            libraries: [
                                .test(
                                    path: try RelativePath(validating: "GoogleMaps.a")
                                ),
                            ]
                        ),
                        linking: .static,
                        moduleMaps: [
                            googleMapsHeadersPath.appending(component: "module.modulemap"),
                        ]
                    ),
                ],
            ]
        )

        var expectedGraph = graph
        expectedGraph.projects = [
            projectPath: .test(
                path: projectPath,
                targets: [
                    .test(
                        name: "App",
                        settings: .test(
                            base: [
                                "OTHER_SWIFT_FLAGS": [
                                    "-Xcc",
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "OTHER_C_FLAGS": [
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "HEADER_SEARCH_PATHS": ["\"$(SRCROOT)/../GoogleMaps.xcframework/ios-arm64/Headers\""],
                            ]
                        )
                    ),
                ]
            ),
        ]

        // When
        let (gotGraph, gotSideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertBetterEqual(
            expectedGraph,
            gotGraph
        )
        XCTAssertBetterEqual(
            [
                .directory(
                    DirectoryDescriptor(path: derivedDirectory.appending(components: "GoogleMaps", "Headers"))
                ),
                .file(
                    FileDescriptor(
                        path: derivedDirectory.appending(components: "GoogleMaps", "Headers", "module.modulemap"),
                        contents: "modulemap".data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedDirectory.appending(components: "GoogleMaps", "Headers", "GoogleMaps.h"),
                        contents: """
                        #import <GMSIndoorBuilding.h>
                        #import <GMSIndoorLevel.h>
                        """.data(using: .utf8)
                    )
                ),
            ],
            gotSideEffects
        )
    }

    func test_map_when_static_xcframework_framework_linked_via_dynamic_xcframework() async throws {
        // Given
        let projectPath = try temporaryPath()
            .appending(component: "Project")
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(
                projectPath.appending(components: Constants.tuistDirectoryName, Constants.SwiftPackageManager.packageSwiftName)
            )
        let googleMapsPath = projectPath
            .parentDirectory
            .appending(component: "GoogleMaps.xcframework")
        let googleMapsHeadersPath = googleMapsPath.appending(components: "ios-arm64", "Headers")
        try await fileSystem.makeDirectory(at: googleMapsHeadersPath)
        try await fileSystem.writeText(
            "modulemap",
            at: googleMapsHeadersPath.appending(component: "module.modulemap")
        )

        let graph: Graph = .test(
            name: "App",
            path: projectPath,
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(
                            name: "App"
                        ),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "App", path: projectPath): [
                    .testXCFramework(
                        path: try temporaryPath()
                            .appending(component: "DynamicFramework.xcframework")
                    ),
                ],
                .testXCFramework(
                    path: try temporaryPath()
                        .appending(component: "DynamicFramework.xcframework")
                ): [
                    .testXCFramework(
                        path: googleMapsPath,
                        infoPlist: .test(
                            libraries: [
                                .test(
                                    identifier: "ios-arm64",
                                    path: try RelativePath(validating: "GoogleMaps.framework/GoogleMaps")
                                ),
                            ]
                        ),
                        linking: .static,
                        moduleMaps: [
                            googleMapsHeadersPath.appending(component: "module.modulemap"),
                        ]
                    ),
                ],
            ]
        )

        var expectedGraph = graph
        expectedGraph.projects = [
            projectPath: .test(
                path: projectPath,
                targets: [
                    .test(
                        name: "App",
                        settings: .test(
                            base: [
                                "FRAMEWORK_SEARCH_PATHS": [
                                    "\"$(SRCROOT)/../GoogleMaps.xcframework/ios-arm64\"",
                                ],
                            ]
                        )
                    ),
                ]
            ),
        ]

        // When
        let (gotGraph, gotSideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertBetterEqual(
            expectedGraph,
            gotGraph
        )
        XCTAssertEmpty(gotSideEffects)
    }

    func test_map_when_static_xcframework_without_umbrella_header_linked_via_dynamic_xcframework() async throws {
        // Given
        let projectPath = try temporaryPath()
            .appending(component: "Project")
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(
                projectPath.appending(components: Constants.tuistDirectoryName, Constants.SwiftPackageManager.packageSwiftName)
            )
        let googleMapsPath = projectPath
            .parentDirectory
            .appending(component: "GoogleMaps.xcframework")
        let googleMapsHeadersPath = googleMapsPath.appending(components: "ios-arm64", "Headers")
        try await fileSystem.makeDirectory(at: googleMapsHeadersPath)
        try await fileSystem.writeText(
            "modulemap",
            at: googleMapsHeadersPath.appending(component: "module.modulemap")
        )

        let derivedDirectory = projectPath.appending(
            components: [
                Constants.tuistDirectoryName,
                Constants.SwiftPackageManager.packageBuildDirectoryName,
                Constants.DerivedDirectory.dependenciesDerivedDirectory,
            ]
        )

        let graph: Graph = .test(
            name: "App",
            path: projectPath,
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(
                            name: "App"
                        ),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "App", path: projectPath): [
                    .testXCFramework(
                        path: try temporaryPath()
                            .appending(component: "DynamicFramework.xcframework")
                    ),
                ],
                .testXCFramework(
                    path: try temporaryPath()
                        .appending(component: "DynamicFramework.xcframework")
                ): [
                    .testXCFramework(
                        path: googleMapsPath,
                        infoPlist: .test(
                            libraries: [
                                .test(
                                    path: try RelativePath(validating: "GoogleMaps.a")
                                ),
                            ]
                        ),
                        linking: .static,
                        moduleMaps: [
                            googleMapsHeadersPath.appending(component: "module.modulemap"),
                        ]
                    ),
                ],
            ]
        )

        var expectedGraph = graph
        expectedGraph.projects = [
            projectPath: .test(
                path: projectPath,
                targets: [
                    .test(
                        name: "App",
                        settings: .test(
                            base: [
                                "OTHER_SWIFT_FLAGS": [
                                    "-Xcc",
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "OTHER_C_FLAGS": [
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "HEADER_SEARCH_PATHS": ["\"$(SRCROOT)/../GoogleMaps.xcframework/ios-arm64/Headers\""],
                            ]
                        )
                    ),
                ]
            ),
        ]

        // When
        let (gotGraph, gotSideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertBetterEqual(
            expectedGraph,
            gotGraph
        )
        XCTAssertBetterEqual(
            [
                .directory(
                    DirectoryDescriptor(path: derivedDirectory.appending(components: "GoogleMaps", "Headers"))
                ),
                .file(
                    FileDescriptor(
                        path: derivedDirectory.appending(components: "GoogleMaps", "Headers", "module.modulemap"),
                        contents: "modulemap".data(using: .utf8)
                    )
                ),
            ],
            gotSideEffects
        )
    }

    func test_map_when_static_xcframework_linked_via_dynamic_xcframework_and_dynamic_framework() async throws {
        // Given
        let projectPath = try temporaryPath()
            .appending(component: "Project")
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(
                projectPath.appending(components: Constants.tuistDirectoryName, Constants.SwiftPackageManager.packageSwiftName)
            )
        let googleMapsPath = projectPath
            .parentDirectory
            .appending(component: "GoogleMaps.xcframework")
        let googleMapsHeadersPath = googleMapsPath.appending(components: "ios-arm64", "Headers")
        try await fileSystem.makeDirectory(at: googleMapsHeadersPath)
        try await fileSystem.writeText(
            "modulemap",
            at: googleMapsHeadersPath.appending(component: "module.modulemap")
        )
        try await fileSystem.writeText(
            """
            #import <GoogleMaps/GMSIndoorBuilding.h>
            #import <GoogleMaps/GMSIndoorLevel.h>
            """,
            at: googleMapsHeadersPath.appending(component: "GoogleMaps.h")
        )

        let graph: Graph = .test(
            name: "App",
            path: projectPath,
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(
                            name: "App"
                        ),
                        .test(
                            name: "DynamicFrameworkOne"
                        ),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "App", path: projectPath): [
                    .target(
                        name: "DynamicFrameworkOne",
                        path: projectPath
                    ),
                ],
                .target(
                    name: "DynamicFrameworkOne",
                    path: projectPath
                ): [
                    .testXCFramework(
                        path: try temporaryPath()
                            .appending(component: "DynamicFrameworkTwo.xcframework")
                    ),
                ],
                .testXCFramework(
                    path: try temporaryPath()
                        .appending(component: "DynamicFrameworkTwo.xcframework")
                ): [
                    .testXCFramework(
                        path: googleMapsPath,
                        infoPlist: .test(
                            libraries: [
                                .test(
                                    path: try RelativePath(validating: "GoogleMaps.a")
                                ),
                            ]
                        ),
                        linking: .static,
                        moduleMaps: [
                            googleMapsHeadersPath.appending(component: "module.modulemap"),
                        ]
                    ),
                ],
            ]
        )

        var expectedGraph = graph
        expectedGraph.projects = [
            projectPath: .test(
                path: projectPath,
                targets: [
                    .test(
                        name: "App",
                        settings: .test(
                            base: [
                                "OTHER_SWIFT_FLAGS": [
                                    "-Xcc",
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "OTHER_C_FLAGS": [
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "HEADER_SEARCH_PATHS": ["\"$(SRCROOT)/../GoogleMaps.xcframework/ios-arm64/Headers\""],
                            ]
                        )
                    ),
                    .test(
                        name: "DynamicFrameworkOne",
                        settings: .test(
                            base: [
                                "OTHER_SWIFT_FLAGS": [
                                    "-Xcc",
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "OTHER_C_FLAGS": [
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "HEADER_SEARCH_PATHS": ["\"$(SRCROOT)/../GoogleMaps.xcframework/ios-arm64/Headers\""],
                            ]
                        )
                    ),
                ]
            ),
        ]

        // When
        let (gotGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertBetterEqual(
            expectedGraph,
            gotGraph
        )
    }

    func test_map_when_static_xcframework_linked_via_static_xcframework() async throws {
        // Given
        let projectPath = try temporaryPath()
            .appending(component: "Project")
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(
                projectPath.appending(components: Constants.tuistDirectoryName, Constants.SwiftPackageManager.packageSwiftName)
            )
        let googleMapsPath = projectPath
            .parentDirectory
            .appending(component: "GoogleMaps.xcframework")

        let graph: Graph = .test(
            name: "App",
            path: projectPath,
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(
                            name: "App"
                        ),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "App", path: projectPath): [
                    .testXCFramework(
                        path: try temporaryPath()
                            .appending(component: "StaticXCFramework.xcframework"),
                        linking: .static
                    ),
                ],
                .testXCFramework(
                    path: try temporaryPath()
                        .appending(component: "StaticXCFramework.xcframework")
                ): [
                    .testXCFramework(
                        path: googleMapsPath,
                        linking: .static
                    ),
                ],
            ]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertBetterEqual(
            graph,
            gotGraph
        )
        XCTAssertEmpty(gotSideEffects)
    }

    func test_removeOtherSwithDuplicates() {
        // Given
        let settings: SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": .array(
                [
                    "value-one",
                    "-Xcc", "value-two",
                    "-Xcc", "value-three",
                    "-Xcc", "value-two",
                    "-I", "value-one",
                    "-I", "value-two",
                    "-Xfrontend", "value-five",
                    "-Xfrontend", "value-five",
                    "-Xfrontend", "value-two",
                    "value-four",
                    "value-one",
                ]
            ),
        ]

        // When
        let got = settings.removeOtherSwiftFlagsDuplicates()

        // Then
        XCTAssertEqual(
            got,
            [
                "OTHER_SWIFT_FLAGS": .array(
                    [
                        "value-one",
                        "-Xcc", "value-two",
                        "-Xcc", "value-three",
                        "-I", "value-one",
                        "-I", "value-two",
                        "-Xfrontend", "value-five",
                        "-Xfrontend", "value-two",
                        "value-four",
                    ]
                ),
            ]
        )
    }
}
