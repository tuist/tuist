import Foundation
import TuistGraph
import TuistSupport
import TuistSupportTesting
import XCTest
@testable import TuistGenerator

final class ExplicitDependencyGraphMapperTests: TuistUnitTestCase {
    private var subject: ExplicitDependencyGraphMapper!

    override public func setUp() {
        super.setUp()
        subject = ExplicitDependencyGraphMapper()
    }

    override public func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_map() async throws {
        // Given
        let projectAPath = fileHandler.currentPath.appending(component: "ProjectA")
        let externalProjectBPath = fileHandler.currentPath.appending(component: "ProjectB")
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
            productName: "DynamicLibraryB"
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
                    isExternal: true
                ),
            ],
            targets: [
                projectAPath: [
                    "FrameworkA": frameworkA,
                    "DynamicLibraryB": dynamicLibraryB,
                ],
                externalProjectBPath: [
                    "ExternalFrameworkC": externalFrameworkC,
                ],
            ],
            dependencies: [
                .target(name: "FrameworkA", path: projectAPath): [
                    .target(name: "DynamicLibraryB", path: projectAPath),
                    .target(name: "ExternalFrameworkC", path: externalProjectBPath),
                ],
            ]
        )

        // When
        let got = try await subject.map(graph: graph)
        let copyScript = """
        if [[ -d "$FILE" && ! -d "$DESTINATION_FILE" ]]; then
            ln -s "$FILE" "$DESTINATION_FILE"
        fi

        if [[ -f "$FILE" && ! -f "$DESTINATION_FILE" ]]; then
            ln -s "$FILE" "$DESTINATION_FILE"
        fi
        """

        // Then
        XCTAssertEqual(
            got.0.projects[projectAPath]?.targets[0],
            .test(
                name: "App",
                product: .app,
                dependencies: [
                    .target(name: "FrameworkA"),
                ]
            )
        )
        let gotFrameworkA = try XCTUnwrap(got.0.projects[projectAPath]?.targets[1])
        XCTAssertEqual(
            gotFrameworkA.name,
            "FrameworkA"
        )
        XCTAssertEqual(
            gotFrameworkA.product,
            .framework
        )
        XCTAssertEqual(
            gotFrameworkA.settings?.baseDebug["BUILT_PRODUCTS_DIR"],
            "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)"
        )
        XCTAssertEqual(
            gotFrameworkA.settings?.baseDebug["TARGET_BUILD_DIR"],
            "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)"
        )
        switch gotFrameworkA.settings?.baseDebug["FRAMEWORK_SEARCH_PATHS"] {
        case let .array(array):
            XCTAssertEqual(
                Set(array),
                Set(
                    [
                        "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/DynamicLibraryB",
                        "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/ExternalFrameworkC",
                    ]
                )
            )
        default:
            XCTFail("Invalid case for FRAMEWORK_SEARCH_PATHS")
        }
        XCTAssertEqual(
            gotFrameworkA.scripts,
            [
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
        )
        XCTAssertEqual(
            gotFrameworkA.dependencies,
            [
                .target(name: "DynamicLibraryB"),
                .project(target: "ExternalFrameworkC", path: externalProjectBPath),
            ]
        )
        XCTAssertEqual(
            got.0.projects[projectAPath]?.targets[2],
            .test(
                name: "DynamicLibraryB",
                product: .dynamicLibrary,
                settings: .test(
                    baseDebug: [
                        "BUILT_PRODUCTS_DIR": "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)",
                        "TARGET_BUILD_DIR": "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)",
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
            )
        )
        XCTAssertEqual(
            got.0.projects[externalProjectBPath]?.targets,
            [
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
            ]
        )
    }
}
