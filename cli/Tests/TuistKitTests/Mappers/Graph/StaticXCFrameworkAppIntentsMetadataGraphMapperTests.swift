import Path
import TuistCore
import TuistTesting
import XcodeGraph
import XCTest
@testable import TuistKit

final class StaticXCFrameworkAppIntentsMetadataGraphMapperTests: TuistUnitTestCase {
    private var subject: StaticXCFrameworkAppIntentsMetadataGraphMapper!

    override func setUp() {
        super.setUp()
        subject = StaticXCFrameworkAppIntentsMetadataGraphMapper()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_map_injects_a_pre_script_when_runnable_target_depends_on_static_xcframework_with_app_intents_metadata()
        async throws
    {
        // Given
        let projectPath = try temporaryPath().appending(component: "Project")
        let intentsXCFrameworkPath = projectPath.parentDirectory.appending(component: "IntentsFramework.xcframework")
        try await fileSystem.makeDirectory(
            at: intentsXCFrameworkPath.appending(components: "ios-arm64", "IntentsFramework.framework", "Metadata.appintents")
        )
        let xcframeworkDependency = try staticXCFrameworkDependency(
            path: intentsXCFrameworkPath,
            frameworkName: "IntentsFramework"
        )

        let graph = Graph.test(
            name: "App",
            path: projectPath,
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(name: "App", product: .app),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "App", path: projectPath): [
                    xcframeworkDependency,
                ],
            ]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let scripts = try XCTUnwrap(gotGraph.projects[projectPath]?.targets["App"]?.scripts)
        let script = try XCTUnwrap(scripts.first(where: { $0.name == "Prepare App Intents Metadata for Static XCFrameworks" }))
        XCTAssertEqual(script.order, .pre)
        XCTAssertEqual(
            script.embeddedScript,
            """
            METADATA_FILE="${TARGET_TEMP_DIR}/${TARGET_NAME}.DependencyMetadataFileList"
            STATIC_METADATA_FILE="${TARGET_TEMP_DIR}/${TARGET_NAME}.DependencyStaticMetadataFileList"

            mkdir -p "$(dirname "$METADATA_FILE")"
            touch "$METADATA_FILE" "$STATIC_METADATA_FILE"

            framework_name='IntentsFramework'
            framework_metadata="${BUILT_PRODUCTS_DIR}/IntentsFramework.framework/Metadata.appintents"
            static_metadata="${BUILT_PRODUCTS_DIR}/IntentsFramework.appintents/Metadata.appintents"

            if [ -d "$framework_metadata" ] && [ ! -d "$static_metadata" ]; then
                mkdir -p "$static_metadata"
                cp -R "$framework_metadata/." "$static_metadata/"
            fi

            framework_actions_data="${framework_metadata}/extract.actionsdata"
            if [ -f "$framework_actions_data" ] && ! grep -qxF "$framework_actions_data" "$METADATA_FILE"; then
                echo "$framework_actions_data" >> "$METADATA_FILE"
            fi

            static_actions_data="${static_metadata}/extract.actionsdata"
            if [ -f "$static_actions_data" ] && ! grep -qxF "$static_actions_data" "$STATIC_METADATA_FILE"; then
                echo "$static_actions_data" >> "$STATIC_METADATA_FILE"
            fi
            """
        )
        XCTAssertEqual(
            script.inputPaths,
            [
                "${BUILT_PRODUCTS_DIR}/IntentsFramework.framework/Metadata.appintents/extract.actionsdata",
                "${BUILT_PRODUCTS_DIR}/IntentsFramework.framework/Metadata.appintents/version.json",
            ]
        )
        XCTAssertEqual(script.outputPaths, [])
        XCTAssertFalse(script.showEnvVarsInLog)
        XCTAssertEqual(script.basedOnDependencyAnalysis, false)
        XCTAssertEmpty(gotSideEffects)
    }

    func test_map_injects_a_single_shell_block_per_framework_when_xcframework_has_multiple_slices() async throws {
        // Given
        let projectPath = try temporaryPath().appending(component: "Project")
        let intentsXCFrameworkPath = projectPath.parentDirectory.appending(component: "IntentsFramework.xcframework")
        try await fileSystem.makeDirectory(
            at: intentsXCFrameworkPath.appending(components: "ios-arm64", "IntentsFramework.framework", "Metadata.appintents")
        )
        try await fileSystem.makeDirectory(
            at: intentsXCFrameworkPath.appending(
                components: "ios-arm64_x86_64-simulator",
                "IntentsFramework.framework",
                "Metadata.appintents"
            )
        )
        let xcframeworkDependency = GraphDependency.testXCFramework(
            path: intentsXCFrameworkPath,
            infoPlist: XCFrameworkInfoPlist(libraries: [
                .test(
                    identifier: "ios-arm64",
                    path: try RelativePath(validating: "IntentsFramework.framework")
                ),
                .test(
                    identifier: "ios-arm64_x86_64-simulator",
                    path: try RelativePath(validating: "IntentsFramework.framework")
                ),
            ]),
            linking: .static
        )

        let graph = Graph.test(
            name: "App",
            path: projectPath,
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(name: "App", product: .app),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "App", path: projectPath): [
                    xcframeworkDependency,
                ],
            ]
        )

        // When
        let (gotGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let scripts = try XCTUnwrap(gotGraph.projects[projectPath]?.targets["App"]?.scripts)
        let script = try XCTUnwrap(scripts.first(where: { $0.name == "Prepare App Intents Metadata for Static XCFrameworks" }))
        let embedded = try XCTUnwrap(script.embeddedScript)
        let occurrences = embedded.components(separatedBy: "framework_name='IntentsFramework'").count - 1
        XCTAssertEqual(occurrences, 1, "The shell block for a framework should appear only once, even when the xcframework exposes multiple slices.")
    }

    func test_map_does_not_inject_a_script_when_metadata_is_not_present() async throws {
        // Given
        let projectPath = try temporaryPath().appending(component: "Project")
        let intentsXCFrameworkPath = projectPath.parentDirectory.appending(component: "IntentsFramework.xcframework")
        try await fileSystem.makeDirectory(at: intentsXCFrameworkPath.appending(component: "ios-arm64"))
        let xcframeworkDependency = try staticXCFrameworkDependency(
            path: intentsXCFrameworkPath,
            frameworkName: "IntentsFramework"
        )

        let graph = Graph.test(
            name: "App",
            path: projectPath,
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(name: "App", product: .app),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "App", path: projectPath): [
                    xcframeworkDependency,
                ],
            ]
        )

        // When
        let (gotGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEmpty(try XCTUnwrap(gotGraph.projects[projectPath]?.targets["App"]?.scripts))
    }

    func test_map_does_not_inject_a_script_for_dynamic_xcframeworks_even_when_metadata_is_present() async throws {
        // Given
        let projectPath = try temporaryPath().appending(component: "Project")
        let intentsXCFrameworkPath = projectPath.parentDirectory.appending(component: "IntentsFramework.xcframework")
        try await fileSystem.makeDirectory(
            at: intentsXCFrameworkPath.appending(components: "ios-arm64", "IntentsFramework.framework", "Metadata.appintents")
        )
        let xcframeworkDependency = try dynamicXCFrameworkDependency(
            path: intentsXCFrameworkPath,
            frameworkName: "IntentsFramework"
        )

        let graph = Graph.test(
            name: "App",
            path: projectPath,
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(name: "App", product: .app),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "App", path: projectPath): [
                    xcframeworkDependency,
                ],
            ]
        )

        // When
        let (gotGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEmpty(try XCTUnwrap(gotGraph.projects[projectPath]?.targets["App"]?.scripts))
    }

    func test_map_injects_a_script_for_transitive_static_xcframework_dependencies() async throws {
        // Given
        let projectPath = try temporaryPath().appending(component: "Project")
        let intentsXCFrameworkPath = projectPath.parentDirectory.appending(component: "IntentsFramework.xcframework")
        try await fileSystem.makeDirectory(
            at: intentsXCFrameworkPath.appending(components: "ios-arm64", "IntentsFramework.framework", "Metadata.appintents")
        )
        let xcframeworkDependency = try staticXCFrameworkDependency(
            path: intentsXCFrameworkPath,
            frameworkName: "IntentsFramework"
        )

        let graph = Graph.test(
            name: "App",
            path: projectPath,
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(name: "App", product: .app),
                        .test(name: "Feature", product: .staticFramework),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "App", path: projectPath): [
                    .target(name: "Feature", path: projectPath),
                ],
                .target(name: "Feature", path: projectPath): [
                    xcframeworkDependency,
                ],
            ]
        )

        // When
        let (gotGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let scripts = try XCTUnwrap(gotGraph.projects[projectPath]?.targets["App"]?.scripts)
        XCTAssertEqual(scripts.filter { $0.name == "Prepare App Intents Metadata for Static XCFrameworks" }.count, 1)
    }

    func test_map_uses_the_framework_product_name_from_the_xcframework_info_plist() async throws {
        // Given
        let projectPath = try temporaryPath().appending(component: "Project")
        let intentsXCFrameworkPath = projectPath.parentDirectory.appending(component: "SearchIntentsBinary.xcframework")
        try await fileSystem.makeDirectory(
            at: intentsXCFrameworkPath.appending(components: "ios-arm64", "SearchIntents.framework", "Metadata.appintents")
        )
        let xcframeworkDependency = try staticXCFrameworkDependency(
            path: intentsXCFrameworkPath,
            frameworkName: "SearchIntents"
        )

        let graph = Graph.test(
            name: "App",
            path: projectPath,
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(name: "App", product: .app),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "App", path: projectPath): [
                    xcframeworkDependency,
                ],
            ]
        )

        // When
        let (gotGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let scripts = try XCTUnwrap(gotGraph.projects[projectPath]?.targets["App"]?.scripts)
        let script = try XCTUnwrap(scripts.first(where: { $0.name == "Prepare App Intents Metadata for Static XCFrameworks" }))
        XCTAssertTrue(script.embeddedScript?.contains("framework_name='SearchIntents'") == true)
        XCTAssertFalse(script.embeddedScript?.contains("framework_name='SearchIntentsBinary'") == true)
    }

    private func staticXCFrameworkDependency(
        path: AbsolutePath,
        frameworkName: String
    ) throws -> GraphDependency {
        .testXCFramework(
            path: path,
            infoPlist: try xcframeworkInfoPlist(frameworkName: frameworkName),
            linking: .static
        )
    }

    private func dynamicXCFrameworkDependency(
        path: AbsolutePath,
        frameworkName: String
    ) throws -> GraphDependency {
        .testXCFramework(
            path: path,
            infoPlist: try xcframeworkInfoPlist(frameworkName: frameworkName),
            linking: .dynamic
        )
    }

    private func xcframeworkInfoPlist(frameworkName: String) throws -> XCFrameworkInfoPlist {
        XCFrameworkInfoPlist(libraries: [
            .test(
                identifier: "ios-arm64",
                path: try RelativePath(validating: "\(frameworkName).framework")
            ),
        ])
    }
}
