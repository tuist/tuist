import Foundation
import Mockable
import Path
import TuistConstants
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

    func test_map_when_static_xcframework_linked_via_cached_dynamic_xcframework_at_different_path() async throws {
        // Given
        // Simulating the scenario where:
        // - App project is at AllInOneTests/
        // - Cached dynamic xcframework (originally a framework target) is at .cache/tuist/Binaries/HASH/
        // - Static xcframework (GoogleMaps) is at BuiltFrameworks/GoogleMaps.xcframework
        //
        // When a framework target gets cached, it becomes an xcframework at a different path.
        // The bug is that HEADER_SEARCH_PATHS for the App target gets calculated relative to
        // the cached xcframework's path instead of relative to the App project's path.
        let basePath = try temporaryPath()
        let appProjectPath = basePath.appending(component: "AllInOneTests")
        let cachedXCFrameworkPath = basePath.appending(
            components: ".cache",
            "tuist",
            "Binaries",
            "HASH",
            "CachedFramework.xcframework"
        )
        let googleMapsPath = basePath.appending(components: "BuiltFrameworks", "GoogleMaps.xcframework")
        let googleMapsHeadersPath = googleMapsPath.appending(components: "ios-arm64", "Headers")

        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(
                appProjectPath.appending(components: Constants.tuistDirectoryName, Constants.SwiftPackageManager.packageSwiftName)
            )

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

        let derivedDirectory = appProjectPath.appending(
            components: [
                Constants.tuistDirectoryName,
                Constants.SwiftPackageManager.packageBuildDirectoryName,
                Constants.DerivedDirectory.dependenciesDerivedDirectory,
            ]
        )

        let graph: Graph = .test(
            name: "App",
            path: appProjectPath,
            projects: [
                appProjectPath: .test(
                    path: appProjectPath,
                    targets: [
                        .test(
                            name: "App"
                        ),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "App", path: appProjectPath): [
                    // Cached dynamic xcframework at a different path
                    .testXCFramework(
                        path: cachedXCFrameworkPath,
                        linking: .dynamic
                    ),
                ],
                .testXCFramework(
                    path: cachedXCFrameworkPath,
                    linking: .dynamic
                ): [
                    // Static xcframework (GoogleMaps) at BuiltFrameworks/
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

        // Expected: paths should be relative to the App project path
        // App is at AllInOneTests/, GoogleMaps is at BuiltFrameworks/
        // So the correct relative path should be ../BuiltFrameworks/GoogleMaps.xcframework/ios-arm64/Headers
        //
        // BUG: The current implementation may produce incorrect paths like:
        // ../../../../BuiltFrameworks/GoogleMaps.xcframework/ios-arm64/Headers
        // which would be relative to the cached xcframework's path instead
        var expectedGraph = graph
        expectedGraph.projects = [
            appProjectPath: .test(
                path: appProjectPath,
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
                                "HEADER_SEARCH_PATHS": [
                                    "\"$(SRCROOT)/../BuiltFrameworks/GoogleMaps.xcframework/ios-arm64/Headers\"",
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

    func test_map_when_static_framework_xcframework_linked_via_cached_dynamic_xcframework_at_different_path() async throws {
        // Given
        // Same scenario but with a .framework bundle (FRAMEWORK_SEARCH_PATHS) instead of .a library
        let basePath = try temporaryPath()
        let appProjectPath = basePath.appending(component: "AllInOneTests")
        let cachedXCFrameworkPath = basePath.appending(
            components: ".cache",
            "tuist",
            "Binaries",
            "HASH",
            "CachedFramework.xcframework"
        )
        let googleMapsPath = basePath.appending(components: "BuiltFrameworks", "GoogleMaps.xcframework")
        let googleMapsHeadersPath = googleMapsPath.appending(components: "ios-arm64", "Headers")

        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(
                appProjectPath.appending(components: Constants.tuistDirectoryName, Constants.SwiftPackageManager.packageSwiftName)
            )

        try await fileSystem.makeDirectory(at: googleMapsHeadersPath)
        try await fileSystem.writeText(
            "modulemap",
            at: googleMapsHeadersPath.appending(component: "module.modulemap")
        )

        let graph: Graph = .test(
            name: "App",
            path: appProjectPath,
            projects: [
                appProjectPath: .test(
                    path: appProjectPath,
                    targets: [
                        .test(
                            name: "App"
                        ),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "App", path: appProjectPath): [
                    .testXCFramework(
                        path: cachedXCFrameworkPath,
                        linking: .dynamic
                    ),
                ],
                .testXCFramework(
                    path: cachedXCFrameworkPath,
                    linking: .dynamic
                ): [
                    // Static xcframework containing a .framework (not .a library)
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

        // Expected: FRAMEWORK_SEARCH_PATHS should be relative to App project
        // App is at AllInOneTests/, GoogleMaps is at BuiltFrameworks/
        // Correct path: ../BuiltFrameworks/GoogleMaps.xcframework/ios-arm64
        var expectedGraph = graph
        expectedGraph.projects = [
            appProjectPath: .test(
                path: appProjectPath,
                targets: [
                    .test(
                        name: "App",
                        settings: .test(
                            base: [
                                "FRAMEWORK_SEARCH_PATHS": [
                                    "\"$(SRCROOT)/../BuiltFrameworks/GoogleMaps.xcframework/ios-arm64\"",
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

    func test_map_when_static_xcframework_linked_via_dynamic_xcframework_with_multiple_app_targets_in_different_projects(
    ) async throws {
        // Given
        // This test verifies that when multiple app targets in different projects depend on the same
        // dynamic xcframework chain, each target gets paths calculated relative to its own project.
        //
        // Structure:
        // - Project1/App1 -> CachedFramework.xcframework (dynamic) -> GoogleMaps.xcframework (static)
        // - Project2/App2 -> CachedFramework.xcframework (dynamic) -> GoogleMaps.xcframework (static)
        //
        // The paths should be calculated relative to each project, not mixed up.
        let basePath = try temporaryPath()
        let project1Path = basePath.appending(component: "Project1")
        let project2Path = basePath.appending(components: "deeply", "nested", "Project2")
        let cachedXCFrameworkPath = basePath.appending(
            components: ".cache",
            "tuist",
            "Binaries",
            "HASH",
            "CachedFramework.xcframework"
        )
        let googleMapsPath = basePath.appending(components: "BuiltFrameworks", "GoogleMaps.xcframework")
        let googleMapsHeadersPath = googleMapsPath.appending(components: "ios-arm64", "Headers")

        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(
                project1Path.appending(components: Constants.tuistDirectoryName, Constants.SwiftPackageManager.packageSwiftName)
            )

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
            name: "Workspace",
            path: basePath,
            projects: [
                project1Path: .test(
                    path: project1Path,
                    targets: [
                        .test(
                            name: "App1"
                        ),
                    ]
                ),
                project2Path: .test(
                    path: project2Path,
                    targets: [
                        .test(
                            name: "App2"
                        ),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "App1", path: project1Path): [
                    .testXCFramework(
                        path: cachedXCFrameworkPath,
                        linking: .dynamic
                    ),
                ],
                .target(name: "App2", path: project2Path): [
                    .testXCFramework(
                        path: cachedXCFrameworkPath,
                        linking: .dynamic
                    ),
                ],
                .testXCFramework(
                    path: cachedXCFrameworkPath,
                    linking: .dynamic
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

        // Expected: Each project should have paths relative to its own path
        // Project1 is at basePath/Project1, GoogleMaps is at basePath/BuiltFrameworks
        // -> HEADER_SEARCH_PATHS: ../BuiltFrameworks/GoogleMaps.xcframework/ios-arm64/Headers
        //
        // Project2 is at basePath/deeply/nested/Project2, GoogleMaps is at basePath/BuiltFrameworks
        // -> HEADER_SEARCH_PATHS: ../../../BuiltFrameworks/GoogleMaps.xcframework/ios-arm64/Headers
        var expectedGraph = graph
        expectedGraph.projects = [
            project1Path: .test(
                path: project1Path,
                targets: [
                    .test(
                        name: "App1",
                        settings: .test(
                            base: [
                                "OTHER_SWIFT_FLAGS": [
                                    "-Xcc",
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "OTHER_C_FLAGS": [
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "HEADER_SEARCH_PATHS": [
                                    "\"$(SRCROOT)/../BuiltFrameworks/GoogleMaps.xcframework/ios-arm64/Headers\"",
                                ],
                            ]
                        )
                    ),
                ]
            ),
            project2Path: .test(
                path: project2Path,
                targets: [
                    .test(
                        name: "App2",
                        settings: .test(
                            base: [
                                "OTHER_SWIFT_FLAGS": [
                                    "-Xcc",
                                    "-fmodule-map-file=\"$(SRCROOT)/../../../Project1/Tuist/.build/tuist-derived/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "OTHER_C_FLAGS": [
                                    "-fmodule-map-file=\"$(SRCROOT)/../../../Project1/Tuist/.build/tuist-derived/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "HEADER_SEARCH_PATHS": [
                                    "\"$(SRCROOT)/../../../BuiltFrameworks/GoogleMaps.xcframework/ios-arm64/Headers\"",
                                ],
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

    func test_map_when_static_xcframework_linked_via_target_with_dynamic_xcframework_dependency() async throws {
        // Given
        // This test reproduces a scenario where:
        // - App (at Project/) depends on CachedFramework target (at .cache/.../HASH/)
        // - CachedFramework target depends on DynamicHelper.xcframework (dynamic)
        // - DynamicHelper.xcframework depends on GoogleMaps.xcframework (static)
        //
        // Both App and CachedFramework should find GoogleMaps through DynamicHelper.
        // CachedFramework's settings would be calculated relative to .cache/.../HASH/.
        // If those settings propagate to App without recalculation, we get wrong paths.
        let basePath = try temporaryPath()
        let appProjectPath = basePath.appending(component: "Project")
        let cachedFrameworkProjectPath = basePath.appending(components: ".cache", "tuist", "Binaries", "HASH")
        let dynamicHelperXCFrameworkPath = basePath.appending(components: "Frameworks", "DynamicHelper.xcframework")
        let googleMapsPath = basePath.appending(components: "BuiltFrameworks", "GoogleMaps.xcframework")
        let googleMapsHeadersPath = googleMapsPath.appending(components: "ios-arm64", "Headers")

        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(
                appProjectPath.appending(components: Constants.tuistDirectoryName, Constants.SwiftPackageManager.packageSwiftName)
            )

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
            name: "Workspace",
            path: basePath,
            projects: [
                appProjectPath: .test(
                    path: appProjectPath,
                    targets: [
                        .test(
                            name: "App"
                        ),
                    ]
                ),
                cachedFrameworkProjectPath: .test(
                    path: cachedFrameworkProjectPath,
                    targets: [
                        .test(
                            name: "CachedFramework",
                            product: .framework
                        ),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "App", path: appProjectPath): [
                    .target(name: "CachedFramework", path: cachedFrameworkProjectPath),
                ],
                .target(name: "CachedFramework", path: cachedFrameworkProjectPath): [
                    .testXCFramework(
                        path: dynamicHelperXCFrameworkPath,
                        linking: .dynamic
                    ),
                ],
                .testXCFramework(
                    path: dynamicHelperXCFrameworkPath,
                    linking: .dynamic
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

        // When
        let (gotGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then - verify the actual behavior:
        // 1. CachedFramework should have settings calculated relative to its project path
        // 2. App should have settings propagated from CachedFramework (combined settings)
        //
        // Key insight: App doesn't directly depend on xcframeworks, so it doesn't get its own
        // `staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies`. Instead, App gets
        // CachedFramework's settings via the settings combination in `mapGraph`.

        // CachedFramework should have paths relative to its project (.cache/.../HASH/)
        let cachedFrameworkSettings = gotGraph.projects[cachedFrameworkProjectPath]?.targets["CachedFramework"]?.settings?.base
        XCTAssertEqual(
            cachedFrameworkSettings?["HEADER_SEARCH_PATHS"],
            .array(["\"$(SRCROOT)/../../../../BuiltFrameworks/GoogleMaps.xcframework/ios-arm64/Headers\""])
        )

        // App gets CachedFramework's settings via combination.
        // The paths should be recalculated relative to App's project path.
        //
        // EXPECTED (CORRECT) BEHAVIOR:
        // App should get ../BuiltFrameworks which is relative to Project/
        let appSettings = gotGraph.projects[appProjectPath]?.targets["App"]?.settings?.base
        let appHeaderSearchPaths = appSettings?["HEADER_SEARCH_PATHS"]

        // App's path should be relative to its own project (Project/), not to CachedFramework's project
        XCTAssertEqual(
            appHeaderSearchPaths,
            .array(["\"$(SRCROOT)/../BuiltFrameworks/GoogleMaps.xcframework/ios-arm64/Headers\""])
        )
    }

    func test_map_when_static_xcframework_library_linked_via_dynamic_xcframework_without_package_manifest() async throws {
        // Given
        let projectPath = try temporaryPath()
            .appending(component: "Project")
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(nil)
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

    func test_map_when_static_xcframework_framework_linked_via_dynamic_xcframework_without_package_manifest() async throws {
        // Given
        let projectPath = try temporaryPath()
            .appending(component: "Project")
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(nil)
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

    func test_removeOtherSwiftDuplicates_preservesEnableUpcomingFeatureFlags() {
        // Given
        let settings: SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": .array(
                [
                    "-enable-upcoming-feature", "DeprecateApplicationMain",
                    "-enable-upcoming-feature", "NonfrozenEnumExhaustivity",
                    "-enable-upcoming-feature", "DeprecateApplicationMain",
                    "-enable-experimental-feature", "StrictConcurrency",
                    "-enable-experimental-feature", "TypedThrows",
                    "-enable-experimental-feature", "StrictConcurrency",
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
                        "-enable-upcoming-feature", "DeprecateApplicationMain",
                        "-enable-upcoming-feature", "NonfrozenEnumExhaustivity",
                        "-enable-experimental-feature", "StrictConcurrency",
                        "-enable-experimental-feature", "TypedThrows",
                    ]
                ),
            ]
        )
    }
}
