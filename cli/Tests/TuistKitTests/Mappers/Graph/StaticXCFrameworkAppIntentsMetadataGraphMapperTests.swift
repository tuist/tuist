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
                    .testXCFramework(path: intentsXCFrameworkPath, linking: .static),
                ],
            ]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let scripts = try XCTUnwrap(gotGraph.projects[projectPath]?.targets["App"]?.scripts)
        let script = try XCTUnwrap(scripts.first(where: { $0.name == "Inject App Intents Metadata from Cached Frameworks" }))
        XCTAssertEqual(script.order, .pre)
        XCTAssertEqual(script.basedOnDependencyAnalysis, false)
        XCTAssertEmpty(gotSideEffects)
    }

    func test_map_does_not_inject_a_script_when_metadata_is_not_present() async throws {
        // Given
        let projectPath = try temporaryPath().appending(component: "Project")
        let intentsXCFrameworkPath = projectPath.parentDirectory.appending(component: "IntentsFramework.xcframework")
        try await fileSystem.makeDirectory(at: intentsXCFrameworkPath.appending(component: "ios-arm64"))

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
                    .testXCFramework(path: intentsXCFrameworkPath, linking: .static),
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
                    .testXCFramework(path: intentsXCFrameworkPath, linking: .dynamic),
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
                    .testXCFramework(path: intentsXCFrameworkPath, linking: .static),
                ],
            ]
        )

        // When
        let (gotGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let scripts = try XCTUnwrap(gotGraph.projects[projectPath]?.targets["App"]?.scripts)
        XCTAssertEqual(scripts.filter { $0.name == "Inject App Intents Metadata from Cached Frameworks" }.count, 1)
    }
}
