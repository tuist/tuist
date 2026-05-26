import Foundation
import Mockable
import Path
import TuistConfig
import TuistConfigLoader
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
    private var configLoader: MockConfigLoading!

    override func setUp() {
        super.setUp()

        manifestFilesLocator = MockManifestFilesLocating()
        configLoader = MockConfigLoading()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(
                .test(project: .generated(.test()))
            )
        subject = StaticXCFrameworkModuleMapGraphMapper(
            manifestFilesLocator: manifestFilesLocator,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        manifestFilesLocator = nil
        configLoader = nil
        subject = nil

        super.tearDown()
    }

    private func makeSubject(configLoader: MockConfigLoading? = nil) -> StaticXCFrameworkModuleMapGraphMapper {
        StaticXCFrameworkModuleMapGraphMapper(
            manifestFilesLocator: manifestFilesLocator,
            configLoader: configLoader ?? self.configLoader
        )
    }

    func test_map_when_dynamic_target_directly_links_static_xcframework_framework() async throws {
        // Given
        let projectPath = try temporaryPath()
            .appending(component: "Project")
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(nil)

        let googleMobileAdsPath = projectPath.parentDirectory
            .appending(component: "GoogleMobileAds.xcframework")
        let moduleMapPath = googleMobileAdsPath.appending(
            components: "ios-arm64", "GoogleMobileAds.framework", "Modules", "module.modulemap"
        )
        try await fileSystem.makeDirectory(at: moduleMapPath.parentDirectory)
        try await fileSystem.writeText(
            """
            framework module GoogleMobileAds {
              link "z"
              link framework "JavaScriptCore"
            }
            """,
            at: moduleMapPath
        )

        let graph: Graph = .test(
            name: "App",
            path: projectPath,
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(
                            name: "Wrapper",
                            product: .framework
                        ),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "Wrapper", path: projectPath): [
                    .testXCFramework(
                        path: googleMobileAdsPath,
                        infoPlist: .test(
                            libraries: [
                                .test(
                                    identifier: "ios-arm64",
                                    path: try RelativePath(validating: "GoogleMobileAds.framework"),
                                    platform: .iOS,
                                    architectures: [.arm64]
                                ),
                            ]
                        ),
                        linking: .static,
                        moduleMaps: [moduleMapPath]
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
                        name: "Wrapper",
                        product: .framework,
                        settings: .test(
                            base: [
                                "OTHER_LDFLAGS[sdk=iphoneos*]": [
                                    "$(inherited)",
                                    "-Wl,-force_load,$(TARGET_BUILD_DIR)/GoogleMobileAds.framework/GoogleMobileAds",
                                    "-lz",
                                    "-framework",
                                    "JavaScriptCore",
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
        XCTAssertBetterEqual(expectedGraph, gotGraph)
        XCTAssertEmpty(gotSideEffects)
    }

    func test_map_when_dynamic_target_directly_links_static_xcframework_uses_matching_slice_module_map() async throws {
        // Given
        let projectPath = try temporaryPath()
            .appending(component: "Project")
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(nil)

        let googleMobileAdsPath = projectPath.parentDirectory
            .appending(component: "GoogleMobileAds.xcframework")
        let iosModuleMapPath = googleMobileAdsPath.appending(
            components: "ios-arm64", "GoogleMobileAds.framework", "Modules", "module.modulemap"
        )
        let macosModuleMapPath = googleMobileAdsPath.appending(
            components: "macos-arm64_x86_64", "GoogleMobileAds.framework", "Modules", "module.modulemap"
        )
        try await fileSystem.makeDirectory(at: iosModuleMapPath.parentDirectory)
        try await fileSystem.makeDirectory(at: macosModuleMapPath.parentDirectory)
        try await fileSystem.writeText(
            """
            framework module GoogleMobileAds {
              link framework "JavaScriptCore"
            }
            """,
            at: iosModuleMapPath
        )
        try await fileSystem.writeText(
            """
            framework module GoogleMobileAds {
              link framework "AppKit"
            }
            """,
            at: macosModuleMapPath
        )

        let graph: Graph = .test(
            name: "App",
            path: projectPath,
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(
                            name: "Wrapper",
                            product: .framework
                        ),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "Wrapper", path: projectPath): [
                    .testXCFramework(
                        path: googleMobileAdsPath,
                        infoPlist: .test(
                            libraries: [
                                .test(
                                    identifier: "ios-arm64",
                                    path: try RelativePath(validating: "GoogleMobileAds.framework"),
                                    platform: .iOS,
                                    architectures: [.arm64]
                                ),
                                .test(
                                    identifier: "macos-arm64_x86_64",
                                    path: try RelativePath(validating: "GoogleMobileAds.framework"),
                                    platform: .macOS,
                                    architectures: [.arm64, .x8664]
                                ),
                            ]
                        ),
                        linking: .static,
                        moduleMaps: [iosModuleMapPath, macosModuleMapPath]
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
                        name: "Wrapper",
                        product: .framework,
                        settings: .test(
                            base: [
                                "OTHER_LDFLAGS[sdk=iphoneos*]": [
                                    "$(inherited)",
                                    "-Wl,-force_load,$(TARGET_BUILD_DIR)/GoogleMobileAds.framework/GoogleMobileAds",
                                    "-framework",
                                    "JavaScriptCore",
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
        XCTAssertBetterEqual(expectedGraph, gotGraph)
        XCTAssertEmpty(gotSideEffects)
    }

    func test_map_when_dynamic_target_directly_links_static_xcframework_library() async throws {
        // Given
        let projectPath = try temporaryPath()
            .appending(component: "Project")
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(nil)

        let googleMobileAdsPath = projectPath.parentDirectory
            .appending(component: "GoogleMobileAds.xcframework")
        let moduleMapPath = googleMobileAdsPath.appending(
            components: "ios-arm64", "Headers", "module.modulemap"
        )
        try await fileSystem.makeDirectory(at: moduleMapPath.parentDirectory)
        try await fileSystem.writeText(
            """
            module GoogleMobileAds {
              link framework "JavaScriptCore"
            }
            """,
            at: moduleMapPath
        )

        let graph: Graph = .test(
            name: "App",
            path: projectPath,
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(
                            name: "Wrapper",
                            product: .framework
                        ),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "Wrapper", path: projectPath): [
                    .testXCFramework(
                        path: googleMobileAdsPath,
                        infoPlist: .test(
                            libraries: [
                                .test(
                                    identifier: "ios-arm64",
                                    path: try RelativePath(validating: "libGoogleMobileAds.a"),
                                    platform: .iOS,
                                    architectures: [.arm64]
                                ),
                            ]
                        ),
                        linking: .static,
                        moduleMaps: [moduleMapPath]
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
                        name: "Wrapper",
                        product: .framework,
                        settings: .test(
                            base: [
                                "OTHER_LDFLAGS[sdk=iphoneos*]": [
                                    "$(inherited)",
                                    "-Wl,-force_load,$(TARGET_BUILD_DIR)/libGoogleMobileAds.a",
                                    "-framework",
                                    "JavaScriptCore",
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
        XCTAssertBetterEqual(expectedGraph, gotGraph)
        XCTAssertEmpty(gotSideEffects)
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
                Constants.DerivedDirectory.dependenciesXCFrameworkDirectory,
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
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/XCFrameworks/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "OTHER_C_FLAGS": [
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/XCFrameworks/GoogleMaps/Headers/module.modulemap\"",
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
                                "FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]": [
                                    "$(inherited)",
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

    func test_map_when_static_xcframework_library_linked_via_dynamic_xcframework_with_custom_scratch_directory()
        async throws
    {
        // Given
        let projectPath = try temporaryPath()
            .appending(component: "Project")
        let customScratchDirectory = projectPath.parentDirectory
            .appending(components: "CustomScratch")
        let customConfigLoader = MockConfigLoading()
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(
                projectPath.appending(components: Constants.tuistDirectoryName, Constants.SwiftPackageManager.packageSwiftName)
            )
        given(customConfigLoader)
            .loadConfig(path: .any)
            .willReturn(
                .test(
                    project: .generated(
                        .test(
                            installOptions: .test(
                                passthroughSwiftPackageManagerArguments: [
                                    "--scratch-path",
                                    customScratchDirectory.pathString,
                                ]
                            )
                        )
                    )
                )
            )
        let subject = makeSubject(configLoader: customConfigLoader)
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

        let derivedDirectory = customScratchDirectory.appending(
            components: [
                Constants.DerivedDirectory.dependenciesDerivedDirectory,
                Constants.DerivedDirectory.dependenciesXCFrameworkDirectory,
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
                                    "-fmodule-map-file=\"$(SRCROOT)/../CustomScratch/tuist-derived/XCFrameworks/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "OTHER_C_FLAGS": [
                                    "-fmodule-map-file=\"$(SRCROOT)/../CustomScratch/tuist-derived/XCFrameworks/GoogleMaps/Headers/module.modulemap\"",
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
        XCTAssertBetterEqual(expectedGraph, gotGraph)
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

    // MARK: - Regression: device vs simulator slice selection (tuist/tuist#9723)

    func test_map_when_static_xcframework_framework_with_device_and_simulator_slices(
    ) async throws {
        // Given
        // An xcframework with both device (ios-arm64) and simulator (ios-arm64-simulator) slices.
        // FRAMEWORK_SEARCH_PATHS must use SDK-conditioned keys so that device and simulator
        // builds each find only the correct binary for their platform.
        let projectPath = try temporaryPath()
            .appending(component: "Project")
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(
                projectPath.appending(
                    components: Constants.tuistDirectoryName,
                    Constants.SwiftPackageManager.packageSwiftName
                )
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
                                    path: try RelativePath(
                                        validating: "GoogleMaps.framework/GoogleMaps"
                                    ),
                                    platform: .iOS,
                                    architectures: [.arm64]
                                ),
                                .test(
                                    identifier: "ios-arm64-simulator",
                                    path: try RelativePath(
                                        validating: "GoogleMaps.framework/GoogleMaps"
                                    ),
                                    platform: .iOS,
                                    platformVariant: .simulator,
                                    architectures: [.arm64]
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
                                "FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]": [
                                    "$(inherited)",
                                    "\"$(SRCROOT)/../GoogleMaps.xcframework/ios-arm64\"",
                                ],
                                "FRAMEWORK_SEARCH_PATHS[sdk=iphonesimulator*]": [
                                    "$(inherited)",
                                    "\"$(SRCROOT)/../GoogleMaps.xcframework/ios-arm64-simulator\"",
                                ],
                            ]
                        )
                    ),
                ]
            ),
        ]

        // When
        let (gotGraph, gotSideEffects, _) = try await subject.map(
            graph: graph,
            environment: MapperEnvironment()
        )

        // Then
        XCTAssertBetterEqual(
            expectedGraph,
            gotGraph
        )
        XCTAssertEmpty(gotSideEffects)
    }

    func test_map_when_static_swift_xcframework_is_reached_through_multiple_paths_deduplicates_search_paths(
    ) async throws {
        // Given
        let projectPath = try temporaryPath()
            .appending(component: "Project")
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(
                projectPath.appending(components: Constants.tuistDirectoryName, Constants.SwiftPackageManager.packageSwiftName)
            )

        let dynamicXCFrameworkPath = projectPath
            .parentDirectory
            .appending(component: "DynamicFramework.xcframework")
        let staticSwiftXCFrameworkPath = projectPath
            .parentDirectory
            .appending(component: "StaticSwift.xcframework")
        let dynamicXCFramework: GraphDependency = .testXCFramework(
            path: dynamicXCFrameworkPath,
            linking: .dynamic
        )
        let staticSwiftXCFramework: GraphDependency = .testXCFramework(
            path: staticSwiftXCFrameworkPath,
            infoPlist: .test(
                libraries: [
                    .test(
                        identifier: "ios-arm64",
                        path: try RelativePath(validating: "StaticSwift.framework/StaticSwift")
                    ),
                ]
            ),
            linking: .static,
            swiftModules: [
                staticSwiftXCFrameworkPath.appending(
                    components: "ios-arm64",
                    "StaticSwift.framework",
                    "Modules",
                    "StaticSwift.swiftmodule"
                ),
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
                        .test(
                            name: "Feature"
                        ),
                        .test(
                            name: "Leaf"
                        ),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "App", path: projectPath): [
                    .target(name: "Feature", path: projectPath),
                    .target(name: "Leaf", path: projectPath),
                ],
                .target(name: "Feature", path: projectPath): [
                    .target(name: "Leaf", path: projectPath),
                ],
                .target(name: "Leaf", path: projectPath): [
                    dynamicXCFramework,
                ],
                dynamicXCFramework: [
                    staticSwiftXCFramework,
                ],
            ]
        )

        let expectedSettings: SettingsDictionary = [
            "FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]": [
                "$(inherited)",
                "\"$(SRCROOT)/../StaticSwift.xcframework/ios-arm64\"",
            ],
        ]
        var expectedGraph = graph
        expectedGraph.projects = [
            projectPath: .test(
                path: projectPath,
                targets: [
                    .test(
                        name: "App",
                        settings: .test(base: expectedSettings)
                    ),
                    .test(
                        name: "Feature",
                        settings: .test(base: expectedSettings)
                    ),
                    .test(
                        name: "Leaf",
                        settings: .test(base: expectedSettings)
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
                Constants.DerivedDirectory.dependenciesXCFrameworkDirectory,
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
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/XCFrameworks/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "OTHER_C_FLAGS": [
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/XCFrameworks/GoogleMaps/Headers/module.modulemap\"",
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
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/XCFrameworks/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "OTHER_C_FLAGS": [
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/XCFrameworks/GoogleMaps/Headers/module.modulemap\"",
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
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/XCFrameworks/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "OTHER_C_FLAGS": [
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/XCFrameworks/GoogleMaps/Headers/module.modulemap\"",
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
                Constants.DerivedDirectory.dependenciesXCFrameworkDirectory,
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
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/XCFrameworks/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "OTHER_C_FLAGS": [
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/XCFrameworks/GoogleMaps/Headers/module.modulemap\"",
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
                                "FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]": [
                                    "$(inherited)",
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
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/XCFrameworks/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "OTHER_C_FLAGS": [
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/XCFrameworks/GoogleMaps/Headers/module.modulemap\"",
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
                                    "-fmodule-map-file=\"$(SRCROOT)/../../../Project1/Tuist/.build/tuist-derived/XCFrameworks/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "OTHER_C_FLAGS": [
                                    "-fmodule-map-file=\"$(SRCROOT)/../../../Project1/Tuist/.build/tuist-derived/XCFrameworks/GoogleMaps/Headers/module.modulemap\"",
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
                Constants.DerivedDirectory.dependenciesXCFrameworkDirectory,
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
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/XCFrameworks/GoogleMaps/Headers/module.modulemap\"",
                                ],
                                "OTHER_C_FLAGS": [
                                    "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/XCFrameworks/GoogleMaps/Headers/module.modulemap\"",
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
                                "FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]": [
                                    "$(inherited)",
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

    func test_removeOtherSwiftDuplicates_when_conditioned_key() {
        // Given
        let settings: SettingsDictionary = [
            "OTHER_SWIFT_FLAGS[sdk=iphoneos*]": .array(
                [
                    "-Xcc", "value-one",
                    "-Xcc", "value-one",
                    "-enable-upcoming-feature", "DeprecateApplicationMain",
                    "-enable-upcoming-feature", "DeprecateApplicationMain",
                    "value-two",
                    "value-two",
                ]
            ),
        ]

        // When
        let got = settings.removeOtherSwiftFlagsDuplicates()

        // Then
        XCTAssertEqual(
            got,
            [
                "OTHER_SWIFT_FLAGS[sdk=iphoneos*]": .array(
                    [
                        "-Xcc", "value-one",
                        "-enable-upcoming-feature", "DeprecateApplicationMain",
                        "value-two",
                    ]
                ),
            ]
        )
    }
}
