import Foundation
import Path
import Testing
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
@testable import TuistGenerator

struct ExplicitDependencyGraphMapperTests {
    private let subject: ExplicitDependencyGraphMapper
    init() {
        subject = ExplicitDependencyGraphMapper()
    }

    @Test
    func test_map() async throws {
        // Given
        let projectAPath = try AbsolutePath(validating: "/tmp/ProjectA")
        let externalProjectBPath = try AbsolutePath(validating: "/tmp/ProjectB")
        let frameworkA: Target = .test(
            name: "FrameworkA",
            product: .framework,
            dependencies: [
                .target(name: "DynamicLibraryB"),
                .project(target: "ExternalFrameworkC", path: externalProjectBPath),
            ]
        )
        let dynamicLibraryB: Target = .test(
            name: "DynamicLibraryB",
            product: .dynamicLibrary,
            productName: "DynamicLibraryB",
            settings: .test(
                configurations: [
                    .debug: .test(),
                    .release: .test(),
                ]
            )
        )
        let externalFrameworkC: Target = .test(
            name: "ExternalFrameworkC",
            product: .staticFramework,
            productName: "ExternalFrameworkC"
        )
        let graph = Graph.test(
            projects: [
                projectAPath: .test(
                    targets: [
                        .test(
                            name: "App",
                            product: .app,
                            dependencies: [
                                .target(name: "FrameworkA"),
                            ]
                        ),
                        frameworkA,
                        dynamicLibraryB,
                    ]
                ),
                externalProjectBPath: .test(
                    targets: [
                        externalFrameworkC,
                    ],
                    type: .external(hash: nil)
                ),
            ],
            dependencies: [
                .target(name: "FrameworkA", path: projectAPath): [
                    .target(name: "DynamicLibraryB", path: projectAPath),
                    .target(name: "ExternalFrameworkC", path: externalProjectBPath),
                ],
            ]
        )

        // When
        let got = try await subject.map(graph: graph, environment: MapperEnvironment())
        let copyScript = """
        if [[ -d "$FILE" && ! -d "$DESTINATION_FILE" ]]; then
            ln -s "$FILE" "$DESTINATION_FILE"
        fi

        if [[ -f "$FILE" && ! -f "$DESTINATION_FILE" ]]; then
            ln -s "$FILE" "$DESTINATION_FILE"
        fi
        """

        // Then
        let gotAProject = try #require(got.0.projects[projectAPath])
        let gotATargets = Array(gotAProject.targets.values).sorted()
        #expect(gotATargets[0] == .test(
            name: "App",
            product: .app,
            dependencies: [
                .target(name: "FrameworkA"),
            ]
        ))
        let gotFrameworkA = try #require(gotATargets[2])
        #expect(gotFrameworkA.name == "FrameworkA")
        #expect(gotFrameworkA.product == .framework)
        #expect(gotFrameworkA.settings?
            .baseDebug["BUILT_PRODUCTS_DIR"] == "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)")
        #expect(gotFrameworkA.settings?
            .baseDebug["TARGET_BUILD_DIR"] == "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)")
        switch gotFrameworkA.settings?.baseDebug["FRAMEWORK_SEARCH_PATHS"] {
        case let .array(array):
            #expect(Set(array) == Set(
                [
                    "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/DynamicLibraryB",
                    "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/ExternalFrameworkC",
                ]
            ))
        default:
            Issue.record("Invalid case for FRAMEWORK_SEARCH_PATHS")
        }
        #expect(gotFrameworkA.scripts == [
            TargetScript(
                name: "Copy Built Products for Explicit Dependencies",
                order: .post,
                script: .embedded("""
                # This script copies built products into the shared directory to be available for app and other targets that don't have scoped directories
                # If you try to archive any of the configurations seen in the output paths, the operation will fail due to `Multiple commands produce` error

                FILE="$BUILD_DIR/Debug$EFFECTIVE_PLATFORM_NAME$TARGET_BUILD_SUBPATH/$PRODUCT_NAME/$PRODUCT_NAME.framework"
                DESTINATION_FILE="$BUILD_DIR/Debug$EFFECTIVE_PLATFORM_NAME$TARGET_BUILD_SUBPATH/$PRODUCT_NAME.framework"
                \(copyScript)
                """),
                inputPaths: [
                    "$(BUILD_DIR)/Debug$(EFFECTIVE_PLATFORM_NAME)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)/$(PRODUCT_NAME).framework",
                ],
                outputPaths: [
                    "$(BUILD_DIR)/Debug$(EFFECTIVE_PLATFORM_NAME)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME).framework",
                ]
            ),
        ])
        #expect(gotFrameworkA.dependencies == [
            .target(name: "DynamicLibraryB"),
            .project(target: "ExternalFrameworkC", path: externalProjectBPath),
        ])

        #expect(gotATargets[1] == .test(
            name: "DynamicLibraryB",
            product: .dynamicLibrary,
            settings: .test(
                baseDebug: [
                    "BUILT_PRODUCTS_DIR": "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)",
                    "TARGET_BUILD_DIR": "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)",
                ],
                configurations: [
                    .debug: .test(),
                    .release: .test(),
                ]
            ),
            scripts: [
                TargetScript(
                    name: "Copy Built Products for Explicit Dependencies",
                    order: .post,
                    script: .embedded("""
                    # This script copies built products into the shared directory to be available for app and other targets that don't have scoped directories
                    # If you try to archive any of the configurations seen in the output paths, the operation will fail due to `Multiple commands produce` error

                    FILE="$BUILD_DIR/Debug$EFFECTIVE_PLATFORM_NAME$TARGET_BUILD_SUBPATH/$PRODUCT_NAME/$PRODUCT_NAME.swiftmodule"
                    DESTINATION_FILE="$BUILD_DIR/Debug$EFFECTIVE_PLATFORM_NAME$TARGET_BUILD_SUBPATH/$PRODUCT_NAME.swiftmodule"
                    \(copyScript)
                    """),
                    inputPaths: [
                        "$(BUILD_DIR)/Debug$(EFFECTIVE_PLATFORM_NAME)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)/$(PRODUCT_NAME).swiftmodule",
                    ],
                    outputPaths: [
                        "$(BUILD_DIR)/Debug$(EFFECTIVE_PLATFORM_NAME)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME).swiftmodule",
                    ]
                ),
            ]
        ))
        let gotExternalBProject = try #require(got.0.projects[externalProjectBPath])
        let gotExternalBTargets = Array(gotExternalBProject.targets.values)
        #expect(gotExternalBTargets == [
            .test(
                name: "ExternalFrameworkC",
                product: .staticFramework,
                productName: "ExternalFrameworkC",
                settings: .test(
                    baseDebug: [
                        "BUILT_PRODUCTS_DIR": "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)",
                        "TARGET_BUILD_DIR": "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)",
                        "FRAMEWORK_SEARCH_PATHS": [
                            "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)",
                        ],
                    ]
                ),
                scripts: [
                    TargetScript(
                        name: "Copy Built Products for Explicit Dependencies",
                        order: .post,
                        script: .embedded("""
                        # This script copies built products into the shared directory to be available for app and other targets that don't have scoped directories
                        # If you try to archive any of the configurations seen in the output paths, the operation will fail due to `Multiple commands produce` error

                        FILE="$BUILD_DIR/Debug$EFFECTIVE_PLATFORM_NAME$TARGET_BUILD_SUBPATH/$PRODUCT_NAME/$PRODUCT_NAME.framework"
                        DESTINATION_FILE="$BUILD_DIR/Debug$EFFECTIVE_PLATFORM_NAME$TARGET_BUILD_SUBPATH/$PRODUCT_NAME.framework"
                        \(copyScript)
                        """),
                        inputPaths: [
                            "$(BUILD_DIR)/Debug$(EFFECTIVE_PLATFORM_NAME)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)/$(PRODUCT_NAME).framework",
                        ],
                        outputPaths: [
                            "$(BUILD_DIR)/Debug$(EFFECTIVE_PLATFORM_NAME)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME).framework",
                        ]
                    ),
                ]
            ),
        ])
    }

    @Test
    func enabling_testing_search_paths() async throws {
        // Given
        let projectAPath = try AbsolutePath(validating: "/tmp/ProjectA")
        let externalProjectBPath = try AbsolutePath(validating: "/tmp/ProjectB")

        let frameworkA: Target = .test(
            name: "FrameworkA",
            product: .framework,
            dependencies: [
                .project(target: "ExternalFrameworkB", path: externalProjectBPath),
            ]
        )

        let externalFrameworkB: Target = .test(
            name: "ExternalFrameworkB",
            product: .staticFramework,
            productName: "ExternalFrameworkB",
            settings: .test(base: ["ENABLE_TESTING_SEARCH_PATHS": .string("YES")])
        )

        let graph = Graph.test(
            projects: [
                projectAPath: .test(
                    targets: [
                        frameworkA,
                    ]
                ),
                externalProjectBPath: .test(
                    targets: [
                        externalFrameworkB,
                    ],
                    type: .external(hash: nil)
                ),
            ],
            dependencies: [
                .target(name: "FrameworkA", path: projectAPath): [
                    .target(name: "ExternalFrameworkB", path: externalProjectBPath),
                ],
            ]
        )

        // When
        let got = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let gotAProject = try #require(got.0.projects[projectAPath])
        let gotATargets = Array(gotAProject.targets.values).sorted()
        let gotFrameworkA = try #require(gotATargets[0])
        #expect(gotFrameworkA.name == "FrameworkA")
        #expect(gotFrameworkA.product == .framework)

        // ENABLE_TESTING_SEARCH_PATHS is propagated from ExternalFrameworkB
        #expect(gotFrameworkA.settings?.baseDebug["ENABLE_TESTING_SEARCH_PATHS"] == .string("YES"))
    }
}
