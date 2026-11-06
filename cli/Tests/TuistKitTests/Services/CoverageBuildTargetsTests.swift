import Foundation
import Path
import Testing
import TuistCore
import XcodeGraph
@testable import TuistKit

struct CoverageBuildTargetsTests {
    @Test func listsTheSchemesClosureWithCachedTargetsSlices() throws {
        let projectPath = try AbsolutePath(validating: "/repo/App")
        let app = Target.test(name: "App", product: .app, sources: [SourceFile(path: "/repo/App/Sources/App.swift")])
        // `Lib` keeps its sources in a buildable folder, as Xcode 16 synchronized groups do.
        let lib = Target.test(
            name: "Lib",
            product: .staticFramework,
            sources: [],
            buildableFolders: [BuildableFolder(
                path: "/repo/App/Lib",
                exceptions: BuildableFolderExceptions(exceptions: []),
                resolvedFiles: [
                    BuildableFolderFile(path: "/repo/App/Lib/Lib.swift", compilerFlags: nil),
                    BuildableFolderFile(path: "/repo/App/Lib/Lib.docc", compilerFlags: nil),
                ]
            )]
        )
        let tests = Target.test(
            name: "AppTests",
            product: .unitTests,
            sources: [SourceFile(path: "/repo/App/Tests/AppTests.swift")]
        )
        let other = Target.test(name: "Other", product: .framework, sources: [SourceFile(path: "/repo/App/Other/Other.swift")])
        let project = Project.test(path: projectPath, targets: [app, lib, tests, other])
        let dependency = { (name: String) in GraphDependency.target(name: name, path: projectPath) }
        let graph = Graph.test(
            projects: [projectPath: project],
            dependencies: [
                dependency("App"): [dependency("Lib")],
                dependency("AppTests"): [dependency("App")],
            ]
        )
        // The generated graph lost `Lib` to the binary cache and links its xcframework instead.
        let xcframework = GraphDependency.XCFramework(
            path: try AbsolutePath(validating: "/cache/abc/Lib.xcframework"),
            infoPlist: .test(libraries: [
                .test(
                    identifier: "ios-arm64-simulator",
                    path: try RelativePath(validating: "Lib.framework"),
                    platform: .iOS,
                    platformVariant: .simulator
                ),
                .test(identifier: "ios-arm64", path: try RelativePath(validating: "Lib.framework"), platform: .iOS),
            ]),
            linking: .static,
            mergeable: false,
            status: .required,
            swiftModules: [],
            moduleMaps: []
        )
        let generatedProject = Project.test(path: projectPath, targets: [app, tests, other])
        let generated = Graph.test(
            projects: [projectPath: generatedProject],
            dependencies: [
                dependency("App"): [.xcframework(xcframework)],
                dependency("AppTests"): [dependency("App")],
            ]
        )
        let scheme = Scheme.test(
            buildAction: .test(targets: [TargetReference(projectPath: projectPath, name: "App")]),
            testAction: .test(targets: [TestableTarget(target: TargetReference(projectPath: projectPath, name: "AppTests"))])
        )

        let targets = CoverageBuildTargets.targets(schemes: [scheme], graph: graph, generatedGraph: generated)

        #expect(targets == [
            CoverageBuildTarget(name: "App.app", isTest: false, files: ["/repo/App/Sources/App.swift"]),
            CoverageBuildTarget(name: "AppTests.xctest", isTest: true, files: ["/repo/App/Tests/AppTests.swift"]),
            CoverageBuildTarget(name: "Lib.framework", isTest: false, files: ["/repo/App/Lib/Lib.swift"], binaries: [
                .init(path: "/cache/abc/Lib.xcframework/ios-arm64-simulator/Lib.framework/Lib", platform: "ios", simulator: true),
                .init(path: "/cache/abc/Lib.xcframework/ios-arm64/Lib.framework/Lib", platform: "ios", simulator: false),
            ]),
        ])
    }
}
