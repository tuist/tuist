import Path
import XcodeGraph
import XCTest
@testable import TuistGenerator

final class GraphExtrasTests: XCTestCase {
    func test_filter_skipMacroSupportTargets_excludes_swiftCompilerPlugin_and_its_transitive_deps() throws {
        // Given
        let projectPath: AbsolutePath = "/Project"
        let externalPath: AbsolutePath = "/External"

        let appTarget = Target.test(name: "MyApp", product: .app)
        let macroPluginTarget = Target.test(name: "MyMacroPlugin", product: .macro)
        let swiftCompilerPluginTarget = Target.test(name: "SwiftCompilerPlugin", product: .staticLibrary)
        let swiftSyntaxMacrosTarget = Target.test(name: "SwiftSyntaxMacros", product: .staticLibrary)
        let swiftSyntaxTarget = Target.test(name: "SwiftSyntax", product: .staticLibrary)

        let project = Project.test(path: projectPath, targets: [appTarget])
        let externalProject = Project.test(
            path: externalPath,
            targets: [macroPluginTarget, swiftCompilerPluginTarget, swiftSyntaxMacrosTarget, swiftSyntaxTarget],
            type: .external(hash: nil)
        )

        let macroPluginDep = GraphDependency.target(name: "MyMacroPlugin", path: externalPath)
        let swiftCompilerPluginDep = GraphDependency.target(name: "SwiftCompilerPlugin", path: externalPath)
        let swiftSyntaxMacrosDep = GraphDependency.target(name: "SwiftSyntaxMacros", path: externalPath)
        let swiftSyntaxDep = GraphDependency.target(name: "SwiftSyntax", path: externalPath)

        let graph = XcodeGraph.Graph.test(
            projects: [projectPath: project, externalPath: externalProject],
            dependencies: [
                .target(name: "MyApp", path: projectPath): [macroPluginDep],
                .target(name: "MyMacroPlugin", path: externalPath): [swiftCompilerPluginDep, swiftSyntaxMacrosDep],
                .target(name: "SwiftCompilerPlugin", path: externalPath): [swiftSyntaxMacrosDep],
                .target(name: "SwiftSyntaxMacros", path: externalPath): [swiftSyntaxDep],
                .target(name: "SwiftSyntax", path: externalPath): [],
            ]
        )

        // When
        let result = graph.filter(
            skipTestTargets: false,
            skipExternalDependencies: false,
            skipMacroSupportTargets: true,
            platformToFilter: nil,
            targetsToFilter: []
        )

        // Then
        let resultTargetNames = Set(result.keys.map(\.target.name))
        XCTAssertTrue(resultTargetNames.contains("MyApp"), "MyApp should remain in the graph")
        XCTAssertTrue(resultTargetNames.contains("MyMacroPlugin"), "Macro plugin target should remain in the graph")
        XCTAssertFalse(resultTargetNames.contains("SwiftCompilerPlugin"), "SwiftCompilerPlugin should be excluded")
        XCTAssertFalse(
            resultTargetNames.contains("SwiftSyntaxMacros"),
            "SwiftSyntaxMacros (transitive dep of SwiftCompilerPlugin) should be excluded"
        )
        XCTAssertFalse(
            resultTargetNames.contains("SwiftSyntax"),
            "SwiftSyntax (transitive dep of SwiftCompilerPlugin) should be excluded"
        )

        let appGraphTarget = try XCTUnwrap(result.keys.first { $0.target.name == "MyApp" })
        XCTAssertTrue(result[appGraphTarget]?.contains(macroPluginDep) == true, "MyApp -> MyMacroPlugin edge should be present")

        let macroGraphTarget = try XCTUnwrap(result.keys.first { $0.target.name == "MyMacroPlugin" })
        let macroDeps = result[macroGraphTarget] ?? []
        XCTAssertFalse(macroDeps.contains(swiftCompilerPluginDep), "MyMacroPlugin -> SwiftCompilerPlugin edge should be removed")
        XCTAssertFalse(macroDeps.contains(swiftSyntaxMacrosDep), "MyMacroPlugin -> SwiftSyntaxMacros edge should be removed")
    }

    func test_filter_skipMacroSupportTargets_false_keeps_swiftCompilerPlugin() throws {
        // Given
        let projectPath: AbsolutePath = "/Project"
        let externalPath: AbsolutePath = "/External"

        let appTarget = Target.test(name: "MyApp", product: .app)
        let swiftCompilerPluginTarget = Target.test(name: "SwiftCompilerPlugin", product: .staticLibrary)

        let project = Project.test(path: projectPath, targets: [appTarget])
        let externalProject = Project.test(
            path: externalPath,
            targets: [swiftCompilerPluginTarget],
            type: .external(hash: nil)
        )

        let swiftCompilerPluginDep = GraphDependency.target(name: "SwiftCompilerPlugin", path: externalPath)

        let graph = XcodeGraph.Graph.test(
            projects: [projectPath: project, externalPath: externalProject],
            dependencies: [
                .target(name: "MyApp", path: projectPath): [swiftCompilerPluginDep],
                .target(name: "SwiftCompilerPlugin", path: externalPath): [],
            ]
        )

        // When
        let result = graph.filter(
            skipTestTargets: false,
            skipExternalDependencies: false,
            skipMacroSupportTargets: false,
            platformToFilter: nil,
            targetsToFilter: []
        )

        // Then
        let resultTargetNames = Set(result.keys.map(\.target.name))
        XCTAssertTrue(resultTargetNames.contains("MyApp"))
        XCTAssertTrue(resultTargetNames.contains("SwiftCompilerPlugin"), "SwiftCompilerPlugin should be kept when flag is false")
    }

    func test_filter_skipMacroSupportTargets_noOp_when_swiftCompilerPlugin_absent() throws {
        // Given
        let projectPath: AbsolutePath = "/Project"

        let appTarget = Target.test(name: "MyApp", product: .app)
        let libTarget = Target.test(name: "MyLib", product: .staticLibrary)

        let project = Project.test(path: projectPath, targets: [appTarget, libTarget])
        let libDep = GraphDependency.target(name: "MyLib", path: projectPath)

        let graph = XcodeGraph.Graph.test(
            projects: [projectPath: project],
            dependencies: [
                .target(name: "MyApp", path: projectPath): [libDep],
                .target(name: "MyLib", path: projectPath): [],
            ]
        )

        // When
        let result = graph.filter(
            skipTestTargets: false,
            skipExternalDependencies: false,
            skipMacroSupportTargets: true,
            platformToFilter: nil,
            targetsToFilter: []
        )

        // Then — nothing is filtered when SwiftCompilerPlugin isn't in the graph
        let resultTargetNames = Set(result.keys.map(\.target.name))
        XCTAssertTrue(resultTargetNames.contains("MyApp"))
        XCTAssertTrue(resultTargetNames.contains("MyLib"))
    }

    func test_filter_skipMacroSupportTargets_does_not_prune_user_target_with_shadowing_name() throws {
        // Given: an internal target named `SwiftSyntax` that shares its name with a transitive
        // dep of `SwiftCompilerPlugin` in an external project. Filtering must key on (path, name)
        // and only drop the external one.
        let projectPath: AbsolutePath = "/Project"
        let externalPath: AbsolutePath = "/External"

        let appTarget = Target.test(name: "MyApp", product: .app)
        let userSwiftSyntaxTarget = Target.test(name: "SwiftSyntax", product: .staticLibrary)
        let swiftCompilerPluginTarget = Target.test(name: "SwiftCompilerPlugin", product: .staticLibrary)
        let externalSwiftSyntaxTarget = Target.test(name: "SwiftSyntax", product: .staticLibrary)

        let project = Project.test(path: projectPath, targets: [appTarget, userSwiftSyntaxTarget])
        let externalProject = Project.test(
            path: externalPath,
            targets: [swiftCompilerPluginTarget, externalSwiftSyntaxTarget],
            type: .external(hash: nil)
        )

        let userSwiftSyntaxDep = GraphDependency.target(name: "SwiftSyntax", path: projectPath)
        let externalSwiftSyntaxDep = GraphDependency.target(name: "SwiftSyntax", path: externalPath)
        let swiftCompilerPluginDep = GraphDependency.target(name: "SwiftCompilerPlugin", path: externalPath)

        let graph = XcodeGraph.Graph.test(
            projects: [projectPath: project, externalPath: externalProject],
            dependencies: [
                .target(name: "MyApp", path: projectPath): [userSwiftSyntaxDep, swiftCompilerPluginDep],
                .target(name: "SwiftSyntax", path: projectPath): [],
                .target(name: "SwiftCompilerPlugin", path: externalPath): [externalSwiftSyntaxDep],
                .target(name: "SwiftSyntax", path: externalPath): [],
            ]
        )

        // When
        let result = graph.filter(
            skipTestTargets: false,
            skipExternalDependencies: false,
            skipMacroSupportTargets: true,
            platformToFilter: nil,
            targetsToFilter: []
        )

        // Then
        let internalKeyExists = result.keys.contains { $0.path == projectPath && $0.target.name == "SwiftSyntax" }
        let externalKeyExists = result.keys.contains { $0.path == externalPath && $0.target.name == "SwiftSyntax" }
        let externalPluginExists = result.keys.contains { $0.path == externalPath && $0.target.name == "SwiftCompilerPlugin" }
        XCTAssertTrue(
            internalKeyExists,
            "User's SwiftSyntax target must remain even though it shares a name with the macro-support transitive dep"
        )
        XCTAssertFalse(externalKeyExists, "External SwiftSyntax (transitive dep of SwiftCompilerPlugin) must be excluded")
        XCTAssertFalse(externalPluginExists, "SwiftCompilerPlugin must be excluded")

        let appGraphTarget = try XCTUnwrap(result.keys.first { $0.target.name == "MyApp" })
        let appDeps = result[appGraphTarget] ?? []
        XCTAssertTrue(appDeps.contains(userSwiftSyntaxDep), "MyApp -> internal SwiftSyntax edge should be preserved")
        XCTAssertFalse(appDeps.contains(swiftCompilerPluginDep), "MyApp -> SwiftCompilerPlugin edge should be removed")
    }

    func test_filter_skipMacroSupportTargets_combined_with_skipExternalDependencies() throws {
        // Given
        let projectPath: AbsolutePath = "/Project"
        let externalPath: AbsolutePath = "/External"

        let appTarget = Target.test(name: "MyApp", product: .app)
        let macroPluginTarget = Target.test(name: "MyMacroPlugin", product: .macro)
        let swiftCompilerPluginTarget = Target.test(name: "SwiftCompilerPlugin", product: .staticLibrary)

        let project = Project.test(path: projectPath, targets: [appTarget])
        let externalProject = Project.test(
            path: externalPath,
            targets: [macroPluginTarget, swiftCompilerPluginTarget],
            type: .external(hash: nil)
        )

        let macroPluginDep = GraphDependency.target(name: "MyMacroPlugin", path: externalPath)
        let swiftCompilerPluginDep = GraphDependency.target(name: "SwiftCompilerPlugin", path: externalPath)

        let graph = XcodeGraph.Graph.test(
            projects: [projectPath: project, externalPath: externalProject],
            dependencies: [
                .target(name: "MyApp", path: projectPath): [macroPluginDep],
                .target(name: "MyMacroPlugin", path: externalPath): [swiftCompilerPluginDep],
                .target(name: "SwiftCompilerPlugin", path: externalPath): [],
            ]
        )

        // When
        let result = graph.filter(
            skipTestTargets: false,
            skipExternalDependencies: true,
            skipMacroSupportTargets: true,
            platformToFilter: nil,
            targetsToFilter: []
        )

        // Then
        let names = Set(result.keys.map(\.target.name))
        XCTAssertTrue(names.contains("MyApp"))
        XCTAssertFalse(names.contains("SwiftCompilerPlugin"))
        XCTAssertFalse(names.contains("MyMacroPlugin"), "External macro plugin pruned via skipExternalDependencies")
    }

    func test_filter_skipMacroSupportTargets_combined_with_targetsToFilter() throws {
        // Given
        let projectPath: AbsolutePath = "/Project"
        let externalPath: AbsolutePath = "/External"

        let appTarget = Target.test(name: "MyApp", product: .app)
        let otherAppTarget = Target.test(name: "OtherApp", product: .app)
        let swiftCompilerPluginTarget = Target.test(name: "SwiftCompilerPlugin", product: .staticLibrary)

        let project = Project.test(path: projectPath, targets: [appTarget, otherAppTarget])
        let externalProject = Project.test(
            path: externalPath,
            targets: [swiftCompilerPluginTarget],
            type: .external(hash: nil)
        )

        let swiftCompilerPluginDep = GraphDependency.target(name: "SwiftCompilerPlugin", path: externalPath)

        let graph = XcodeGraph.Graph.test(
            projects: [projectPath: project, externalPath: externalProject],
            dependencies: [
                .target(name: "MyApp", path: projectPath): [swiftCompilerPluginDep],
                .target(name: "OtherApp", path: projectPath): [swiftCompilerPluginDep],
                .target(name: "SwiftCompilerPlugin", path: externalPath): [],
            ]
        )

        // When: only MyApp requested + macro support skipped
        let result = graph.filter(
            skipTestTargets: false,
            skipExternalDependencies: false,
            skipMacroSupportTargets: true,
            platformToFilter: nil,
            targetsToFilter: ["MyApp"]
        )

        // Then
        let names = Set(result.keys.map(\.target.name))
        XCTAssertTrue(names.contains("MyApp"))
        XCTAssertFalse(names.contains("OtherApp"), "Filtered out by targetsToFilter")
        XCTAssertFalse(names.contains("SwiftCompilerPlugin"), "Filtered out by skipMacroSupportTargets")
    }
}
